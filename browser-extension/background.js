"use strict";
importScripts("payload.js", "gemini-parser.js", "claude-parser.js", "provider-requests.js");
const hosts = { gemini: "https://gemini.google.com", claude: "https://claude.ai" };
const alarmName = "usage-refresh";
const bridgeURL = "http://127.0.0.1:49627/v1/usage";
const flights = new Map(), deliveries = new Map(), contexts = new Set(), fallbacks = new Map();
const providerRevision = { gemini: 0, claude: 0 };
let connectionRevision = 0, alarmCheck = null;
async function current(context) {
  if (context.connection !== connectionRevision || context.revision !== providerRevision[context.provider] || context.controller.signal.aborted) return false;
  const { pairingToken } = await chrome.storage.local.get("pairingToken");
  return pairingToken === context.token && context.connection === connectionRevision && context.revision === providerRevision[context.provider] && !context.controller.signal.aborted;
}
async function contextFor(provider) {
  const connection = connectionRevision, revision = providerRevision[provider];
  const { pairingToken } = await chrome.storage.local.get("pairingToken");
  if (!pairingToken || connection !== connectionRevision || revision !== providerRevision[provider]) return null;
  const context = { provider, token: pairingToken, connection, revision, startedAt: Date.now() / 1000, controller: new AbortController() };
  contexts.add(context);
  return context;
}
function invalidateConnection() {
  connectionRevision += 1;
  for (const context of contexts) context.controller.abort();
  flights.clear();
}
async function setStatus(provider, status, deliveredAt = null, context = null) {
  if (context && !await current(context)) return;
  await chrome.storage.local.set({ [`status_${provider}`]: { status, checkedAt: Date.now(), deliveredAt } });
}
async function selectedTab(provider) {
  const tabs = await chrome.tabs.query({ url: `${hosts[provider]}/*` });
  return tabs.sort((a, b) => Number(b.active) - Number(a.active) || (b.lastAccessed || 0) - (a.lastAccessed || 0) || b.id - a.id)[0];
}
function accountIndexFromURL(url) {
  const page = new URL(url);
  if (page.origin !== hosts.gemini) return undefined;
  const pathIndex = page.pathname.match(/^\/u\/([^/]+)(?:\/|$)/)?.[1];
  const value = pathIndex ?? page.searchParams.get("authuser");
  return value === null ? null : /^\d{1,3}$/.test(value) ? value : undefined;
}
async function rememberAccount(url, preserveFlight = false) {
  const connection = connectionRevision, revision = providerRevision.gemini;
  const index = accountIndexFromURL(url);
  if (index === undefined) return false;
  const stored = await chrome.storage.local.get("geminiAccountIndex");
  if (connection !== connectionRevision || revision !== providerRevision.gemini) return null;
  const previous = typeof stored.geminiAccountIndex === "string" && /^\d{1,3}$/.test(stored.geminiAccountIndex) ? stored.geminiAccountIndex : null;
  if (previous === index) return true;
  providerRevision.gemini += 1;
  for (const context of contexts) if (context.provider === "gemini") context.controller.abort();
  if (!preserveFlight) flights.delete("gemini");
  if (index === null) await chrome.storage.local.remove("geminiAccountIndex");
  else await chrome.storage.local.set({ geminiAccountIndex: index });
  return true;
}
async function deliverNow(clean, context) {
  if (!await current(context)) return { ok: false, status: "superseded" };
  const timestamp = clean.updatedAt ?? context.startedAt;
  const key = `lastDelivered_${clean.provider}`;
  const previous = (await chrome.storage.local.get(key))[key] ?? 0;
  if (timestamp <= previous || !await current(context)) return { ok: false, status: "stale" };
  try {
    const response = await fetch(bridgeURL, { method: "POST", credentials: "omit",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${context.token}` },
      body: JSON.stringify(clean), signal: AbortSignal.any([context.controller.signal, AbortSignal.timeout(6000)]), redirect: "error" });
    if (!await current(context)) return { ok: false, status: "superseded" };
    if (!response.ok) {
      const status = response.status === 401 || response.status === 403 ? "pairing_rejected" : "bridge_error";
      await setStatus(clean.provider, status, null, context);
      return { ok: false, status };
    }
    await chrome.storage.local.set({ [key]: timestamp });
    const status = clean.error || "delivered";
    await setStatus(clean.provider, status, clean.error ? null : Date.now(), context);
    return { ok: true, status };
  } catch {
    await setStatus(clean.provider, "bridge_unavailable", null, context);
    return { ok: false, status: "bridge_unavailable" };
  }
}
function deliver(payload, context) {
  const clean = AIUsagePayload.sanitize(payload);
  // Serialize native POSTs per provider so a late tab reply cannot overwrite a
  // newer direct read. Persist only the delivery timestamp, never quota bodies.
  const pending = (deliveries.get(clean.provider) || Promise.resolve()).catch(() => {}).then(() => deliverNow(clean, context));
  deliveries.set(clean.provider, pending);
  return pending.finally(() => { if (deliveries.get(clean.provider) === pending) deliveries.delete(clean.provider); });
}
async function tabFallback(provider, context) {
  const tab = await selectedTab(provider);
  if (!tab || tab.discarded || tab.frozen || !await current(context)) return false;
  const requestId = crypto.randomUUID();
  const pending = { requestId, tabId: tab.id, context };
  fallbacks.set(provider, pending);
  let timeout;
  try {
    const reply = await Promise.race([
      chrome.tabs.sendMessage(tab.id, { type: "refresh", provider, requestId }),
      new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error("timeout")), 23000); })
    ]);
    return reply?.ok === true;
  } catch { return false; }
  finally {
    clearTimeout(timeout);
    if (fallbacks.get(provider) === pending) fallbacks.delete(provider);
  }
}
async function refreshOnce(provider) {
  const connection = connectionRevision, revision = providerRevision[provider];
  const storedToken = (await chrome.storage.local.get("pairingToken")).pairingToken;
  if (connection !== connectionRevision || revision !== providerRevision[provider]) return;
  if (!storedToken) { await setStatus(provider, "not_configured"); return; }
  if (provider === "gemini") {
    const tab = await selectedTab(provider);
    if (connection !== connectionRevision || revision !== providerRevision[provider]) return;
    const remembered = tab?.url ? await rememberAccount(tab.url, true) : true;
    if (remembered === null) return;
    if (!remembered) {
      const context = await contextFor(provider);
      if (context) { try { await deliver({ provider, error: "select_account" }, context); } finally { contexts.delete(context); } }
      return;
    }
  }
  const context = await contextFor(provider);
  if (!context) return;
  try {
    await setStatus(provider, "fetching", null, context);
    const stored = await chrome.storage.local.get("geminiAccountIndex");
    const accountIndex = typeof stored.geminiAccountIndex === "string" && /^\d{1,3}$/.test(stored.geminiAccountIndex) ? stored.geminiAccountIndex : null;
    context.accountIndex = accountIndex;
    try {
      const payload = await AIUsageRequests.fetchUsage(provider, { accountIndex, signal: context.controller.signal });
      return await deliver(payload, context);
    } catch (error) {
      if (!await current(context)) return;
      const code = ["auth_required", "rate_limited", "schema_changed", "select_account", "network"].includes(error?.code) ? error.code : "network";
      // Cookie policies may reject extension-origin reads. Fall back only to an
      // already live tab; never open, reload, or wake the user's tabs.
      if (["auth_required", "network"].includes(code) && await tabFallback(provider, context)) return;
      return await deliver({ provider, error: code }, context);
    }
  } finally { contexts.delete(context); }
}
function refresh(provider) {
  if (flights.has(provider)) return flights.get(provider);
  const pending = refreshOnce(provider).finally(() => { if (flights.get(provider) === pending) flights.delete(provider); });
  flights.set(provider, pending);
  return pending;
}
async function refreshAll() { await Promise.allSettled(Object.keys(hosts).map(refresh)); }
async function forward(payload, sender, requestId) {
  if (!sender.tab || !Object.hasOwn(hosts, payload?.provider) || new URL(sender.url).origin !== hosts[payload.provider]) throw new Error("invalid_sender");
  const pending = fallbacks.get(payload.provider);
  if (!pending || pending.requestId !== requestId || pending.tabId !== sender.tab.id || !await current(pending.context)) return { ok: false, status: "unsolicited" };
  const selected = await selectedTab(payload.provider);
  if (selected?.id !== sender.tab.id || !await current(pending.context)) return { ok: false, status: "inactive_tab" };
  if (payload.provider === "gemini" && accountIndexFromURL(sender.url) !== pending.context.accountIndex) return { ok: false, status: "superseded" };
  const clean = AIUsagePayload.sanitize(payload);
  // The original read context carries its token/account generation. A reply
  // from before disconnect/re-pair must never inherit a newer connection.
  return deliver(clean, pending.context);
}
async function handle(message, sender) {
  if (sender.id !== chrome.runtime.id) throw new Error("invalid_sender");
  if (message?.type === "usage") return forward(message.payload, sender, message.requestId);
  if (message?.type === "provider-ready") {
    if (!Object.hasOwn(hosts, message.provider) || !sender.tab || new URL(sender.url).origin !== hosts[message.provider]) throw new Error("invalid_sender");
    const ready = Boolean((await chrome.storage.local.get("pairingToken")).pairingToken) && (await selectedTab(message.provider))?.id === sender.tab.id;
    if (!ready) return { read: false };
    if (message.provider === "gemini" && !await rememberAccount(sender.url)) return { read: false };
    // Tab loading is a prompt refresh trigger. Only an explicitly requested,
    // correlated fallback is allowed to fetch inside the content script.
    refresh(message.provider).catch(() => {});
    return { read: false };
  }
  if (sender.tab || sender.url !== chrome.runtime.getURL("popup.html")) throw new Error("invalid_sender");
  if (message?.type === "status") {
    const stored = await chrome.storage.local.get(["pairingToken", "status_gemini", "status_claude", "geminiAccountIndex"]);
    const accountIndex = typeof stored.geminiAccountIndex === "string" && /^\d{1,3}$/.test(stored.geminiAccountIndex) ? stored.geminiAccountIndex : null;
    return { configured: Boolean(stored.pairingToken), gemini: stored.status_gemini, claude: stored.status_claude,
      geminiAccountIndex: accountIndex, geminiAccountMode: accountIndex === null ? "default" : "selected",
      nextRefreshAt: (await chrome.alarms.get(alarmName))?.scheduledTime ?? null };
  }
  if (message?.type === "save-token") {
    const token = typeof message.token === "string" ? message.token.trim() : "";
    if (!/^[!-~]{32,256}$/.test(token)) return { ok: false, error: "invalid_token" };
    invalidateConnection();
    await chrome.storage.local.set({ pairingToken: token });
    await ensureAlarm();
    await refreshAll();
    return { ok: true };
  }
  if (message?.type === "disconnect") {
    invalidateConnection();
    const connection = connectionRevision;
    await chrome.storage.local.remove("pairingToken");
    if (connection === connectionRevision) await Promise.all(Object.keys(hosts).map(provider => setStatus(provider, "not_configured")));
    return { ok: true };
  }
  if (message?.type === "refresh-all") { await ensureAlarm(); await refreshAll(); return { ok: true }; }
  throw new Error("invalid_message");
}
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  handle(message, sender).then(respond).catch(() => respond({ ok: false, error: "invalid_request" }));
  return true;
});
function ensureAlarm() {
  if (alarmCheck) return alarmCheck;
  alarmCheck = (async () => {
    const alarm = await chrome.alarms.get(alarmName);
    if (!alarm || alarm.periodInMinutes !== 5) await chrome.alarms.create(alarmName, { periodInMinutes: 5 });
  })().finally(() => { alarmCheck = null; });
  return alarmCheck;
}
async function start() { await ensureAlarm(); await refreshAll(); }
chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === alarmName) return refreshAll(); });
chrome.runtime.onInstalled.addListener(start);
chrome.runtime.onStartup.addListener(start);
// A popup status read can wake this worker. Repair the schedule without treating
// that observation as a usage refresh; the five-minute alarm does the polling.
ensureAlarm();
