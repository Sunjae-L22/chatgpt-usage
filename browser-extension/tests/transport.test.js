"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const id = "a".repeat(32);
const popupSender = { id, url: `chrome-extension://${id}/popup.html` };
const contentSender = { id, url: "https://gemini.google.com/app/example", tab: { id: 7 } };
function harness({ token = "t".repeat(64), httpStatus = 200, tabs = [{ id: 7, active: true }] } = {}) {
  const values = token ? { pairingToken: token } : {};
  const requests = [];
  const listeners = {};
  const event = name => ({ addListener(fn) { listeners[name] = fn; } });
  const chrome = {
    storage: { local: {
      async get(keys) { return Object.fromEntries((Array.isArray(keys) ? keys : [keys]).map(key => [key, values[key]])); },
      async set(value) { Object.assign(values, value); },
      async remove(key) { delete values[key]; }
    } },
    tabs: { async query() { return structuredClone(tabs); }, async sendMessage() {} },
    alarms: { async get() { return {}; }, async create() {}, onAlarm: event("alarm") },
    runtime: { id, getURL: file => `chrome-extension://${id}/${file}`, onMessage: event("message"), onInstalled: event("install"), onStartup: event("startup") }
  };
  let context;
  context = vm.createContext({ chrome, URL, Date, AbortSignal,
    fetch: async (url, options) => { requests.push({ url, ...options }); return { ok: httpStatus >= 200 && httpStatus < 300, status: httpStatus }; },
    importScripts: file => vm.runInContext(fs.readFileSync(path.join(__dirname, "..", file), "utf8"), context)
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, "../background.js"), "utf8"), context);
  return { values, requests, send(message, sender = contentSender) {
    return new Promise(resolve => listeners.message(message, sender, resolve));
  } };
}
const payload = () => ({ provider: "gemini", plan: null,
  windows: [{ id: "GXU_WEEKLY", label: null, usedPercent: 42.5, windowDurationMins: 10080, resetsAt: null }],
  updatedAt: Date.now() / 1000, source: "Gemini web", cookie: "must-never-leave", email: "fixture@example.invalid" });
test("Transport sends authenticated loopback JSON and strips page extras", async () => {
  const testBridge = harness();
  const result = await testBridge.send({ type: "usage", payload: payload() });
  assert.equal(result.ok, true);
  assert.equal(testBridge.requests.length, 1);
  const request = testBridge.requests[0];
  assert.equal(request.url, "http://127.0.0.1:49627/v1/usage");
  assert.equal(request.headers.Authorization, `Bearer ${"t".repeat(64)}`);
  assert.equal(request.credentials, "omit");
  assert.equal(request.redirect, "error");
  assert.equal(request.body.includes("must-never-leave"), false);
  assert.equal(request.body.includes("fixture@example.invalid"), false);
  assert.equal(testBridge.values.status_gemini.status, "delivered");
});
test("Wrong sender, different provider host and inactive tabs cannot deliver usage", async () => {
  const testBridge = harness();
  for (const sender of [
    { ...contentSender, id: "b".repeat(32) },
    { ...contentSender, url: "https://example.invalid/" },
    { ...contentSender, url: "https://claude.ai/new" },
    { ...contentSender, tab: { id: 8 } }, popupSender
  ]) assert.equal((await testBridge.send({ type: "usage", payload: payload() }, sender)).ok, false);
  assert.equal(testBridge.requests.length, 0);
});
test("Unpaired extension does not query on content load or forward usage", async () => {
  const testBridge = harness({ token: null });
  assert.equal((await testBridge.send({ type: "provider-ready", provider: "gemini" })).read, false);
  assert.equal((await testBridge.send({ type: "usage", payload: payload() })).ok, false);
  assert.equal(testBridge.requests.length, 0);
  assert.equal(testBridge.values.status_gemini.status, "not_configured");
});
test("Native auth rejection is not reported as connected", async () => {
  const testBridge = harness({ httpStatus: 401 });
  const result = await testBridge.send({ type: "usage", payload: payload() });
  assert.equal(result.status, "pairing_rejected");
  assert.equal(testBridge.values.status_gemini.deliveredAt, null);
});
test("Only popup may change or remove pairing token; status never returns token", async () => {
  const testBridge = harness();
  assert.equal((await testBridge.send({ type: "disconnect" })).ok, false);
  assert.equal(testBridge.values.pairingToken, "t".repeat(64));
  const state = await testBridge.send({ type: "status" }, popupSender);
  assert.equal(state.configured, true);
  assert.equal(JSON.stringify(state).includes("t".repeat(64)), false);
  assert.equal((await testBridge.send({ type: "save-token", token: "too-short" }, popupSender)).ok, false);
  assert.equal((await testBridge.send({ type: "disconnect" }, popupSender)).ok, true);
  assert.equal(testBridge.values.pairingToken, undefined);
});
test("Provider errors are delivered without raw responses or extra fields", async () => {
  const testBridge = harness();
  await testBridge.send({ type: "usage", payload: { provider: "gemini", error: "auth_required", raw: "private upstream response" } });
  assert.deepEqual(JSON.parse(testBridge.requests[0].body), { provider: "gemini", error: "auth_required" });
  assert.equal(testBridge.values.status_gemini.status, "auth_required");
});
