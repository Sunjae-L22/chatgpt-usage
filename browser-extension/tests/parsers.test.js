"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const gemini = require("../gemini-parser.js");
const claude = require("../claude-parser.js");
const { sanitize } = require("../payload.js");
const fixture = name => fs.readFileSync(path.join(__dirname, "../fixtures", name), "utf8");
const now = 1792224000;
const changeGemini = modify => {
  const parsed = JSON.parse(fixture("gemini-usage.json"));
  modify(parsed[0].data.viewer.rpcs.getUsageInfo.pools);
  return JSON.stringify(parsed);
};
const error = code => value => value.code === code;
test("Gemini fractions become real percentages and only verified scopes survive", () => {
  const result = gemini.parse(fixture("gemini-usage.json"), now);
  assert.equal(result.provider, "gemini");
  assert.equal(result.plan, null);
  assert.deepEqual(result.windows.map(w => [w.id, w.usedPercent, w.windowDurationMins]), [
    ["GXU_FIVE_HOURLY", 42.5, 300], ["GXU_WEEKLY", 63, 10080]
  ]);
  assert.equal(result.windows[0].resetsAt, Date.parse("2026-10-17T12:00:00.125Z") / 1000);
});
test("Gemini accepts XSSI prefix and explicit zero without inventing missing usage", () => {
  assert.equal(gemini.parse(")]}'\n" + fixture("gemini-usage.json"), now).windows.length, 2);
  assert.equal(gemini.parse(changeGemini(pools => { pools[0].percentageUsed = 0; }), now).windows[0].usedPercent, 0);
  for (const value of [null, undefined, "0.42", -0.1, 42.5, Infinity]) {
    assert.throws(() => gemini.parse(changeGemini(pools => { pools[0].percentageUsed = value; }), now), error("schema_changed"));
  }
});
test("Gemini handles authentication, malformed schema, unknown pools and duplicates", () => {
  for (const text of ["<html>Sign in</html>", '[{"data":{"viewer":null}}]']) assert.throws(() => gemini.parse(text), error("auth_required"));
  for (const text of ["null", "{}", "not json", "[]", '[{"data":{"viewer":{}}}]']) assert.throws(() => gemini.parse(text), error("schema_changed"));
  assert.throws(() => gemini.parse(changeGemini(pools => { pools.splice(0, 2); })), error("schema_changed"));
  assert.throws(() => gemini.parse(changeGemini(pools => { pools.push(pools[0]); })), error("schema_changed"));
});
test("Missing reset stays null, never a fabricated reset time", () => {
  for (const value of [null, undefined, "tomorrow", "2026-bad"]) {
    assert.equal(gemini.parse(changeGemini(pools => { pools[0].gxu.windowRefreshesAt = value; }), now).windows[0].resetsAt, null);
  }
});
test("Gemini endpoint preserves only numeric account indices", () => {
  const first = new URL(gemini.url("https://gemini.google.com/u/2/app/test"));
  assert.equal(first.origin, "https://gemini.google.com");
  assert.equal(first.searchParams.get("authuser"), "2");
  assert.equal(new URL(gemini.url("https://gemini.google.com/usage?authuser=fixture@example.invalid")).searchParams.has("authuser"), false);
  assert.equal(new URL(gemini.url("https://gemini.google.com/u/1")).searchParams.get("authuser"), "1");
});
test("Claude parser retains numeric precision and whitelists quota windows", () => {
  const result = claude.parse(fixture("claude-usage.json"), now);
  assert.equal(result.windows.length, 3);
  assert.equal(result.windows[0].usedPercent, 42.5);
  assert.equal(result.windows[2].label, "Sonnet");
  assert.equal(JSON.stringify(result).includes("fixture-only"), false);
  assert.equal(JSON.stringify(result).includes("credits"), false);
});
test("Claude does not guess organizations or fill missing values with zero", () => {
  const organization = { uuid: "01234567-89ab-cdef-0123-456789abcdef", name: "Fixture" };
  assert.equal(claude.organization(JSON.stringify([organization])), organization.uuid);
  assert.throws(() => claude.organization(JSON.stringify([organization, organization])), error("select_account"));
  assert.throws(() => claude.organization("[]"), error("auth_required"));
  assert.throws(() => claude.organization('[{"uuid":"../other"}]'), error("schema_changed"));
  for (const utilization of [null, "1", -1, 101]) assert.throws(() => claude.parse(JSON.stringify({ five_hour: { utilization } })), error("schema_changed"));
  assert.throws(() => claude.parse('{"five_hour":null}'), error("schema_changed"));
  assert.throws(() => claude.parse("<html>Login</html>"), error("auth_required"));
});
test("Transport projection strips every non-quota field", () => {
  const parsed = gemini.parse(fixture("gemini-usage.json"), now);
  parsed.email = "fixture@example.invalid";
  parsed.cookie = "fixture-only";
  parsed.plan = "unverified";
  parsed.windows[0].secret = "fixture-only";
  const clean = sanitize(parsed, now);
  assert.deepEqual(Object.keys(clean).sort(), ["plan", "provider", "source", "updatedAt", "windows"]);
  assert.equal(clean.plan, null);
  assert.equal(JSON.stringify(clean).includes("fixture-only"), false);
});
test("Transport rejects stale, malformed, unknown and duplicate data", () => {
  const parsed = () => gemini.parse(fixture("gemini-usage.json"), now);
  for (const modify of [
    data => { data.provider = "__proto__"; }, data => { data.provider = "unknown"; },
    data => { data.updatedAt = now - 121; }, data => { data.updatedAt = now + 61; },
    data => { data.windows[0].usedPercent = NaN; }, data => { data.windows[0].windowDurationMins = 10080; },
    data => { data.windows[0].resetsAt = -1; }, data => { data.windows[1] = data.windows[0]; },
    data => { data.windows[0].id = "__proto__"; }
  ]) { const data = parsed(); modify(data); assert.throws(() => sanitize(data, now), /invalid_payload/); }
  assert.deepEqual(sanitize({ provider: "gemini", error: "auth_required", raw: "sensitive" }, now), { provider: "gemini", error: "auth_required" });
});
test("Manifest grants only provider hosts, local bridge, storage and alarms", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "../manifest.json"), "utf8"));
  assert.deepEqual(manifest.permissions.sort(), ["alarms", "storage"]);
  assert.deepEqual(manifest.host_permissions.sort(), ["http://127.0.0.1:49627/*", "https://claude.ai/*", "https://gemini.google.com/*"]);
  assert.equal(manifest.externally_connectable, undefined);
});
