"use strict";
importScripts("payload.js");
const hosts = { gemini: "https://gemini.google.com", claude: "https://claude.ai" };
const alarmName = "usage-refresh";
const bridgeURL = "http://127.0.0.1:49627/v1/usage";
async function setStatus(provider, status, deliveredAt = null) {
  await chrome.storage.local.set({ [`status_${provider}`]: { status, checkedAt: Date.now(), deliveredAt } });
}
async function selectedTab(provider) {
  const tabs = await chrome.tabs.query({ url: `${hosts[provider]}/*` });
  return tabs.sort((a, b) => Number(b.active) - Number(a.active) || (b.lastAccessed || 0) - (a.lastAccessed || 0) || b.id - a.id)[0];
}
async function configured() { return Boolean((await chrome.storage.local.get("pairingToken")).pairingToken); }
async function refresh(provider) {
  if (!await configured()) { await setStatus(provider, "not_configured"); return; }
  const tab = await selectedTab(provider);
  if (!tab) { await setStatus(provider, "waiting_for_tab"); return; }
  await setStatus(provider, "fetching");
  try { await chrome.tabs.sendMessage(tab.id, { type: "refresh", provider }); }
  catch { await setStatus(provider, "reload_tab"); }
}
async function refreshAll() { await Promise.all(Object.keys(hosts).map(refresh)); }
async function forward(payload, sender) {
  if (!sender.tab || new URL(sender.url).origin !== hosts[payload?.provider]) throw new Error("invalid_sender");
  const selected = await selectedTab(payload.provider);
  if (selected?.id !== sender.tab.id) return { ok: false, status: "inactive_tab" };
  const clean = AIUsagePayload.sanitize(payload);
  const { pairingToken } = await chrome.storage.local.get("pairingToken");
  if (!pairingToken) { await setStatus(clean.provider, "not_configured"); return { ok: false }; }
  try {
    const response = await fetch(bridgeURL, { method: "POST", credentials: "omit",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${pairingToken}` },
      body: JSON.stringify(clean), signal: AbortSignal.timeout(6000), redirect: "error" });
    if (!response.ok) {
      const status = response.status === 401 || response.status === 403 ? "pairing_rejected" : "bridge_error";
      await setStatus(clean.provider, status);
      return { ok: false, status };
    }
    const status = clean.error || "delivered";
    await setStatus(clean.provider, status, clean.error ? null : Date.now());
    return { ok: true, status };
  } catch {
    await setStatus(clean.provider, "bridge_unavailable");
    return { ok: false, status: "bridge_unavailable" };
  }
}
async function handle(message, sender) {
  if (sender.id !== chrome.runtime.id) throw new Error("invalid_sender");
  if (message?.type === "usage") return forward(message.payload, sender);
  if (message?.type === "provider-ready") {
    if (!Object.hasOwn(hosts, message.provider) || !sender.tab || new URL(sender.url).origin !== hosts[message.provider]) throw new Error("invalid_sender");
    const read = await configured() && (await selectedTab(message.provider))?.id === sender.tab.id;
    if (read) await setStatus(message.provider, "fetching");
    return { read };
  }
  // Settings can only come from this extension's popup, never a web content script.
  if (sender.tab || sender.url !== chrome.runtime.getURL("popup.html")) throw new Error("invalid_sender");
  if (message?.type === "status") {
    const stored = await chrome.storage.local.get(["pairingToken", "status_gemini", "status_claude"]);
    return { configured: Boolean(stored.pairingToken), gemini: stored.status_gemini, claude: stored.status_claude };
  }
  if (message?.type === "save-token") {
    const token = typeof message.token === "string" ? message.token.trim() : "";
    if (!/^[!-~]{32,256}$/.test(token)) return { ok: false, error: "invalid_token" };
    await chrome.storage.local.set({ pairingToken: token });
    await refreshAll();
    return { ok: true };
  }
  if (message?.type === "disconnect") {
    await chrome.storage.local.remove("pairingToken");
    await Promise.all(Object.keys(hosts).map(provider => setStatus(provider, "not_configured")));
    return { ok: true };
  }
  if (message?.type === "refresh-all") { await refreshAll(); return { ok: true }; }
  throw new Error("invalid_message");
}
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  handle(message, sender).then(respond).catch(() => respond({ ok: false, error: "invalid_request" }));
  return true;
});
async function ensureAlarm() {
  if (!await chrome.alarms.get(alarmName)) await chrome.alarms.create(alarmName, { periodInMinutes: 5 });
}
chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === alarmName) refreshAll(); });
chrome.runtime.onInstalled.addListener(ensureAlarm);
chrome.runtime.onStartup.addListener(ensureAlarm);
ensureAlarm();
