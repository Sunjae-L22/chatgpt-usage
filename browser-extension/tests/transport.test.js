"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { webcrypto } = require("node:crypto");
const gemini = require("../gemini-parser.js");
const id = "a".repeat(32), token = "t".repeat(64);
const popup = { id, url: `chrome-extension://${id}/popup.html` };
const fixture = name => fs.readFileSync(path.join(__dirname, "../fixtures", name), "utf8");
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const settle = () => new Promise(resolve => setImmediate(resolve));
function harness({ configured = true, tabs = [], nativeStatus = 200, providerFetch, sendToTab, storageGet, tabQuery, alarm = { name: "usage-refresh", periodInMinutes: 5, scheduledTime: Date.now() + 300000 } } = {}) {
  const values = configured ? { pairingToken: token } : {};
  const requests = [], providerRequests = [], tabMessages = [], createdAlarms = [], listeners = {};
  let openTabs = tabs, currentAlarm = alarm;
  const event = name => ({ addListener(fn) { listeners[name] = fn; } });
  const send = (message, sender = popup) => new Promise(resolve => listeners.message(message, sender, resolve));
  const defaultProvider = async url => {
    if (url.startsWith("https://gemini.google.com/")) return new Response(fixture("gemini-usage.json"));
    if (url === "https://claude.ai/api/organizations") return new Response('[{"uuid":"01234567-89ab-cdef-0123-456789abcdef"}]');
    return new Response(fixture("claude-usage.json"));
  };
  const chrome = {
    storage: { local: {
      async get(keys) {
        const result = Object.fromEntries((Array.isArray(keys) ? keys : [keys]).map(key => [key, values[key]]));
        return storageGet ? storageGet(keys, result) : result;
      },
      async set(value) { Object.assign(values, value); }, async remove(key) { delete values[key]; }
    } },
    tabs: {
      async query({ url }) {
        const result = structuredClone(openTabs.filter(tab => !tab.url || tab.url.startsWith(url.slice(0, -1))));
        return tabQuery ? tabQuery(url, result) : result;
      },
      async sendMessage(tabId, message) { tabMessages.push({ tabId, ...message }); return sendToTab ? sendToTab(tabId, message, send) : Promise.reject(new Error("no receiver")); }
    },
    alarms: {
      async get() { return currentAlarm; },
      async create(name, options) { createdAlarms.push({ name, ...options }); currentAlarm = { name, ...options, scheduledTime: Date.now() + options.periodInMinutes * 60000 }; },
      onAlarm: event("alarm")
    },
    runtime: { id, getURL: file => `chrome-extension://${id}/${file}`, onMessage: event("message"), onInstalled: event("install"), onStartup: event("startup") }
  };
  let context;
  context = vm.createContext({ chrome, URL, Date, AbortSignal, AbortController, TextDecoder, TextEncoder, setTimeout, clearTimeout, crypto: webcrypto,
    fetch: async (url, options) => {
      if (url === "http://127.0.0.1:49627/v1/usage") { requests.push({ url, ...options }); return { ok: nativeStatus >= 200 && nativeStatus < 300, status: nativeStatus }; }
      providerRequests.push({ url, ...options });
      return providerFetch ? providerFetch(url, options, defaultProvider) : defaultProvider(url);
    },
    importScripts: (...files) => files.forEach(file => vm.runInContext(fs.readFileSync(path.join(__dirname, "..", file), "utf8"), context))
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, "../background.js"), "utf8"), context);
  return { values, requests, providerRequests, tabMessages, createdAlarms, send,
    setTabs(tabs) { openTabs = tabs; }, async fire(name, arg) { await listeners[name](arg); await settle(); } };
}
test("Five-minute alarm reads both providers with zero tabs and posts sanitized summaries", async () => {
  const bridge = harness();
  await bridge.fire("alarm", { name: "usage-refresh" });
  assert.equal(bridge.providerRequests.length, 3);
  assert.equal(bridge.requests.length, 2);
  assert.equal(bridge.tabMessages.length, 0);
  for (const request of bridge.requests) {
    assert.equal(request.headers.Authorization, `Bearer ${token}`);
    assert.equal(request.credentials, "omit");
    assert.equal(request.redirect, "error");
    assert.equal(request.body.includes("fixture-only"), false);
    assert.equal(request.body.includes("01234567-89ab"), false);
  }
  assert.equal(bridge.values.status_gemini.status, "delivered");
  assert.equal(bridge.values.status_claude.status, "delivered");
});
test("Startup and install refresh automatically; status reads never trigger polling", async () => {
  for (const name of ["startup", "install"]) {
    const bridge = harness();
    await bridge.fire(name);
    assert.equal(bridge.requests.length, 2);
  }
  const bridge = harness();
  const state = await bridge.send({ type: "status" });
  assert.equal(bridge.providerRequests.length, 0);
  assert.equal(state.configured, true);
  assert.equal(state.geminiAccountMode, "default");
  assert.ok(state.nextRefreshAt > Date.now());
  assert.equal(JSON.stringify(state).includes(token), false);
});
test("Missing or incorrect alarm is repaired, correct alarm is not rescheduled", async () => {
  for (const alarm of [null, { periodInMinutes: 1 }]) {
    const bridge = harness({ alarm }); await settle();
    assert.deepEqual(bridge.createdAlarms, [{ name: "usage-refresh", periodInMinutes: 5 }]);
  }
  const bridge = harness(); await settle();
  assert.equal(bridge.createdAlarms.length, 0);
  await bridge.fire("alarm", { name: "some-other-alarm" });
  assert.equal(bridge.providerRequests.length, 0);
});
test("Concurrent manual refresh and alarm deduplicate each provider", async () => {
  const gate = deferred();
  const bridge = harness({ providerFetch: async (url, _options, base) => { await gate.promise; return base(url); } });
  const alarm = bridge.fire("alarm", { name: "usage-refresh" });
  const manual = bridge.send({ type: "refresh-all" });
  await settle();
  assert.equal(bridge.providerRequests.length, 2);
  gate.resolve(); await Promise.all([alarm, manual]);
  assert.equal(bridge.providerRequests.length, 3);
  assert.equal(bridge.requests.length, 2);
});
test("Disconnect cancels reads and late responses cannot send or overwrite status", async () => {
  const gate = deferred();
  const bridge = harness({ providerFetch: async (url, _options, base) => { await gate.promise; return base(url); } });
  const pending = bridge.fire("alarm", { name: "usage-refresh" });
  await settle();
  await bridge.send({ type: "disconnect" });
  gate.resolve(); await pending;
  assert.equal(bridge.requests.length, 0);
  assert.equal(bridge.values.status_gemini.status, "not_configured");
  assert.equal(bridge.values.status_claude.status, "not_configured");
  assert.ok(bridge.providerRequests.every(request => request.signal.aborted));
});
test("Rotating pairing code invalidates the old refresh and starts new reads", async () => {
  const gate = deferred(); let old = true;
  const bridge = harness({ providerFetch: async (url, _options, base) => { if (old) await gate.promise; return base(url); } });
  const pending = bridge.fire("alarm", { name: "usage-refresh" });
  await settle(); old = false;
  await bridge.send({ type: "save-token", token: "n".repeat(64) });
  gate.resolve(); await pending;
  assert.equal(bridge.requests.length, 2);
  assert.ok(bridge.requests.every(request => request.headers.Authorization === `Bearer ${"n".repeat(64)}`));
});
test("Unpaired alarms and content messages never fetch or post", async () => {
  const bridge = harness({ configured: false });
  await bridge.fire("alarm", { name: "usage-refresh" });
  assert.equal(bridge.providerRequests.length, 0);
  assert.equal(bridge.requests.length, 0);
  assert.equal(bridge.values.status_gemini.status, "not_configured");
});
test("Wrong senders cannot change settings or push unsolicited quota", async () => {
  const bridge = harness();
  const sender = { id, url: "https://gemini.google.com/usage", tab: { id: 7 } };
  for (const message of [{ type: "disconnect" }, { type: "save-token", token: "n".repeat(64) }, { type: "usage", payload: gemini.parse(fixture("gemini-usage.json")) }]) {
    assert.equal((await bridge.send(message, sender)).ok, false);
  }
  assert.equal((await bridge.send({ type: "disconnect" }, { ...popup, id: "b".repeat(32) })).ok, false);
  assert.equal(bridge.values.pairingToken, token);
  assert.equal(bridge.requests.length, 0);
});
test("Native authentication failure is reported without claiming delivery", async () => {
  const bridge = harness({ nativeStatus: 401 });
  await bridge.fire("alarm", { name: "usage-refresh" });
  assert.equal(bridge.values.status_gemini.status, "pairing_rejected");
  assert.equal(bridge.values.status_gemini.deliveredAt, null);
});
test("Only correlated fallback replies are accepted and their raw extras are stripped", async () => {
  let seenRequest;
  const sender = { id, url: "https://gemini.google.com/usage", tab: { id: 7 } };
  const bridge = harness({ tabs: [{ id: 7, active: true, url: sender.url }],
    providerFetch: async (url, _options, base) => url.startsWith("https://gemini") ? new Response("private", { status: 403 }) : base(url),
    sendToTab: async (_tab, message, send) => {
      seenRequest = message.requestId;
      const payload = { ...gemini.parse(fixture("gemini-usage.json")), cookie: "never-forward", raw: "private" };
      assert.equal((await send({ type: "usage", payload, requestId: "wrong" }, sender)).ok, false);
      return send({ type: "usage", payload, requestId: message.requestId }, sender);
    }
  });
  await bridge.fire("alarm", { name: "usage-refresh" });
  assert.equal(bridge.requests.length, 2);
  assert.equal(bridge.values.status_gemini.status, "delivered");
  assert.equal(bridge.requests.some(request => request.body.includes("private") || request.body.includes("never-forward")), false);
  const late = await bridge.send({ type: "usage", payload: gemini.parse(fixture("gemini-usage.json")), requestId: seenRequest }, sender);
  assert.equal(late.ok, false);
  assert.equal(bridge.requests.length, 2);
});
test("Frozen/discarded tabs cannot stall direct-read failure handling", async () => {
  for (const flags of [{ frozen: true }, { discarded: true }]) {
    const bridge = harness({ tabs: [{ id: 7, active: true, url: "https://gemini.google.com/usage", ...flags }],
      providerFetch: async (url, _options, base) => url.startsWith("https://gemini") ? new Response("", { status: 401 }) : base(url) });
    await bridge.fire("alarm", { name: "usage-refresh" });
    assert.equal(bridge.tabMessages.length, 0);
    assert.equal(bridge.values.status_gemini.status, "auth_required");
  }
});
test("Numeric Gemini account is retained with no tabs; returning to default clears it", async () => {
  const bridge = harness({ tabs: [{ id: 7, active: true, url: "https://gemini.google.com/u/2/app" }] });
  await bridge.fire("alarm", { name: "usage-refresh" });
  assert.equal(bridge.values.geminiAccountIndex, "2");
  bridge.setTabs([]);
  await bridge.fire("alarm", { name: "usage-refresh" });
  const reads = bridge.providerRequests.filter(request => request.url.startsWith("https://gemini"));
  assert.ok(reads.every(request => new URL(request.url).searchParams.get("authuser") === "2"));
  bridge.setTabs([{ id: 8, active: true, url: "https://gemini.google.com/usage" }]);
  await bridge.fire("alarm", { name: "usage-refresh" });
  assert.equal(bridge.values.geminiAccountIndex, undefined);
  assert.equal((await bridge.send({ type: "status" })).geminiAccountMode, "default");
});
test("Inactive and email-selected Gemini tabs cannot change saved numeric account", async () => {
  const bridge = harness({ tabs: [{ id: 7, active: true, url: "https://gemini.google.com/u/2/app" }] });
  bridge.values.geminiAccountIndex = "2";
  await bridge.send({ type: "provider-ready", provider: "gemini" }, { id, url: "https://gemini.google.com/u/1/app", tab: { id: 8 } });
  assert.equal(bridge.values.geminiAccountIndex, "2");
  bridge.setTabs([{ id: 9, active: true, url: "https://gemini.google.com/usage?authuser=fixture@example.invalid" }]);
  await bridge.fire("alarm", { name: "usage-refresh" });
  assert.equal(bridge.values.geminiAccountIndex, "2");
  assert.equal(bridge.values.status_gemini.status, "select_account");
  assert.equal(bridge.providerRequests.some(request => request.url.includes("fixture@example.invalid")), false);
});
test("An account switch aborts an old read before a different account can be posted", async () => {
  const gate = deferred(); let old = true;
  const bridge = harness({ tabs: [{ id: 7, active: true, url: "https://gemini.google.com/u/1/app" }],
    providerFetch: async (url, _options, base) => { if (old && url.startsWith("https://gemini")) await gate.promise; return base(url); } });
  const pending = bridge.fire("alarm", { name: "usage-refresh" });
  await settle(); old = false;
  bridge.setTabs([{ id: 8, active: true, url: "https://gemini.google.com/u/2/app" }]);
  await bridge.send({ type: "provider-ready", provider: "gemini" }, { id, url: "https://gemini.google.com/u/2/app", tab: { id: 8 } });
  await settle(); gate.resolve(); await pending; await settle();
  assert.equal(bridge.values.geminiAccountIndex, "2");
  assert.equal(bridge.requests.filter(request => JSON.parse(request.body).provider === "gemini").length, 1);
});
test("Delayed unpaired storage read cannot erase a newly connected status", async () => {
  const gate = deferred(); let held = false;
  const bridge = harness({ configured: false, storageGet: async (keys, result) => {
    if (keys === "pairingToken" && !result.pairingToken && !held) { held = true; await gate.promise; }
    return result;
  } });
  const pending = bridge.fire("alarm", { name: "usage-refresh" });
  await settle();
  await bridge.send({ type: "save-token", token });
  assert.equal(bridge.values.status_gemini.status, "delivered");
  gate.resolve(); await pending;
  assert.equal(bridge.values.status_gemini.status, "delivered");
  assert.equal(bridge.values.status_claude.status, "delivered");
});
test("A delayed tab query cannot roll the selected Google account back", async () => {
  const gate = deferred(); let held = false;
  const bridge = harness({ tabs: [{ id: 7, active: true, url: "https://gemini.google.com/u/1/app" }],
    tabQuery: async (url, result) => { if (url.startsWith("https://gemini") && !held) { held = true; await gate.promise; } return result; } });
  const pending = bridge.fire("alarm", { name: "usage-refresh" });
  await settle();
  bridge.setTabs([{ id: 8, active: true, url: "https://gemini.google.com/u/2/app" }]);
  await bridge.send({ type: "provider-ready", provider: "gemini" }, { id, url: "https://gemini.google.com/u/2/app", tab: { id: 8 } });
  await settle(); gate.resolve(); await pending; await settle();
  assert.equal(bridge.values.geminiAccountIndex, "2");
  const reads = bridge.providerRequests.filter(request => request.url.startsWith("https://gemini"));
  assert.equal(reads.length, 1);
  assert.equal(new URL(reads[0].url).searchParams.get("authuser"), "2");
});
test("Old fallback result is rejected after disconnect and re-pair", async () => {
  const fallback = deferred(), ready = deferred(); let rejectGemini = true, oldRequest;
  const sender = { id, url: "https://gemini.google.com/usage", tab: { id: 7 } };
  const bridge = harness({ tabs: [{ id: 7, active: true, url: sender.url }],
    providerFetch: async (url, _options, base) => rejectGemini && url.startsWith("https://gemini") ? new Response("", { status: 403 }) : base(url),
    sendToTab: async (_tab, message) => { oldRequest = message.requestId; ready.resolve(); return fallback.promise; }
  });
  const pending = bridge.fire("alarm", { name: "usage-refresh" });
  await ready.promise;
  await bridge.send({ type: "disconnect" });
  rejectGemini = false;
  await bridge.send({ type: "save-token", token: "n".repeat(64) });
  const before = bridge.requests.length;
  const reply = await bridge.send({ type: "usage", payload: gemini.parse(fixture("gemini-usage.json")), requestId: oldRequest }, sender);
  assert.equal(reply.ok, false);
  fallback.resolve(reply); await pending;
  assert.equal(bridge.requests.length, before);
  assert.equal(bridge.values.status_gemini.status, "delivered");
});
test("A fallback cannot publish from a tab that is no longer selected", async () => {
  const sender = { id, url: "https://gemini.google.com/u/1/app", tab: { id: 7 } };
  let bridge;
  bridge = harness({ tabs: [{ id: 7, active: true, url: sender.url }],
    providerFetch: async (url, _options, base) => url.startsWith("https://gemini") ? new Response("", { status: 403 }) : base(url),
    sendToTab: async (_tab, message, send) => {
      bridge.setTabs([{ id: 8, active: true, url: "https://gemini.google.com/u/2/app" }]);
      return send({ type: "usage", payload: gemini.parse(fixture("gemini-usage.json")), requestId: message.requestId }, sender);
    }
  });
  await bridge.fire("alarm", { name: "usage-refresh" });
  const posted = bridge.requests.map(request => JSON.parse(request.body));
  assert.equal(posted.some(payload => payload.provider === "gemini" && payload.windows), false);
});
