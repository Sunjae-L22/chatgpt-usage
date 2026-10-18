"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { createClient } = require("../provider-requests.js");

const fixture = name => fs.readFileSync(path.join(__dirname, "../fixtures", name), "utf8");
const organizationID = "01234567-89ab-cdef-0123-456789abcdef";
const organizations = JSON.stringify([{ uuid: organizationID, name: "Fixture account" }]);
const byteLimit = 2 * 1024 * 1024;
const hasCode = code => error => error?.code === code;

function fixtureClient(responses) {
  const requests = [];
  const client = createClient(async (url, options) => {
    requests.push({ url: String(url), ...options });
    assert.ok(responses.length, "Unexpected additional provider request");
    const response = responses.shift();
    if (response instanceof Error) throw response;
    return typeof response === "string" ? new Response(response) : response;
  });
  return { client, requests };
}

function assertPrivateRead(request, expectedOrigin) {
  assert.equal(new URL(request.url).origin, expectedOrigin);
  assert.equal(request.method ?? "GET", "GET");
  assert.equal(request.credentials, "include");
  assert.equal(request.cache, "no-store");
  assert.equal(request.redirect, "error");
  assert.ok(request.signal instanceof AbortSignal);
  assert.equal(request.body, undefined);
  const headers = new Headers(request.headers);
  assert.equal(headers.get("accept"), "application/json");
  assert.equal(headers.has("cookie"), false);
  assert.equal(headers.has("authorization"), false);
}

test("Background Gemini request reads the fixed endpoint without any open tab", async () => {
  const { client, requests } = fixtureClient([fixture("gemini-usage.json")]);
  const result = await client.fetchUsage("gemini", { accountIndex: "2" });
  assert.equal(result.provider, "gemini");
  assert.equal(result.windows[0].usedPercent, 42.5);
  assert.equal(requests.length, 1);
  assertPrivateRead(requests[0], "https://gemini.google.com");
  const endpoint = new URL(requests[0].url);
  assert.equal(endpoint.pathname, "/_/BardChatUi/graphql/schemas/GEMINI_WEB_GRAPHQL/executeQuery");
  assert.equal(endpoint.searchParams.get("authuser"), "2");
  assert.ok(endpoint.searchParams.get("query_signature"));
  assert.equal(JSON.stringify(result).includes("Fixture account"), false);
});

test("Gemini account selection cannot inject URLs or send email identifiers", async () => {
  for (const accountIndex of [null, undefined, "fixture@example.invalid", "https://example.invalid/", "../0", "0&secret=private", "1000", "-1"]) {
    const { client, requests } = fixtureClient([fixture("gemini-usage.json")]);
    await client.fetchUsage("gemini", { accountIndex });
    const endpoint = new URL(requests[0].url);
    assert.equal(endpoint.origin, "https://gemini.google.com");
    assert.equal(endpoint.searchParams.has("authuser"), false);
    assert.equal(requests[0].url.includes("example.invalid"), false);
  }
  for (const accountIndex of ["0", "1", "999"]) {
    const { client, requests } = fixtureClient([fixture("gemini-usage.json")]);
    await client.fetchUsage("gemini", { accountIndex });
    assert.equal(new URL(requests[0].url).searchParams.get("authuser"), accountIndex);
  }
});

test("Claude requests only its validated single organization and usage endpoint", async () => {
  const { client, requests } = fixtureClient([organizations, fixture("claude-usage.json")]);
  const result = await client.fetchUsage("claude");
  assert.equal(result.provider, "claude");
  assert.equal(result.windows[0].usedPercent, 42.5);
  assert.deepEqual(requests.map(request => request.url), [
    "https://claude.ai/api/organizations",
    `https://claude.ai/api/organizations/${organizationID}/usage`
  ]);
  for (const request of requests) assertPrivateRead(request, "https://claude.ai");
  assert.equal(JSON.stringify(result).includes(organizationID), false);
  assert.equal(JSON.stringify(result).includes("Fixture account"), false);
});

test("Ambiguous or invalid Claude organizations never trigger a usage request", async () => {
  for (const [body, code] of [
    ["[]", "auth_required"],
    [JSON.stringify([{ uuid: organizationID }, { uuid: organizationID }]), "select_account"],
    [JSON.stringify([{ uuid: "../other/usage" }]), "schema_changed"],
    [JSON.stringify([{ uuid: "https://example.invalid/" }]), "schema_changed"]
  ]) {
    const { client, requests } = fixtureClient([body]);
    await assert.rejects(client.fetchUsage("claude"), hasCode(code));
    assert.equal(requests.length, 1);
  }
});

test("HTTP failures become safe provider error codes without response details", async () => {
  for (const [status, code] of [[401, "auth_required"], [403, "auth_required"], [429, "rate_limited"], [500, "network"], [404, "network"]]) {
    const { client } = fixtureClient([new Response("private upstream response", { status })]);
    await assert.rejects(client.fetchUsage("gemini"), error => {
      assert.equal(error.code, code);
      assert.equal(String(error).includes("private upstream response"), false);
      return true;
    });
  }
});

test("Login HTML and broken JSON remain authentication or schema failures", async () => {
  for (const [body, code] of [["<html>Login needed</html>", "auth_required"], ["not-json", "schema_changed"]]) {
    const { client } = fixtureClient([body]);
    await assert.rejects(client.fetchUsage("gemini"), hasCode(code));
  }
});

test("Response limit rejects advertised and actual oversized bodies in bytes", async () => {
  const oversized = JSON.parse(fixture("gemini-usage.json"));
  oversized[0].ignored = "한".repeat(800000);
  const oversizedText = JSON.stringify(oversized);
  assert.ok(oversizedText.length < byteLimit);
  assert.ok(Buffer.byteLength(oversizedText) > byteLimit);
  for (const response of [
    new Response(fixture("gemini-usage.json"), { headers: { "content-length": String(byteLimit + 1) } }),
    new Response(oversizedText),
    new Response(oversizedText, { headers: { "content-length": "1" } })
  ]) {
    const { client } = fixtureClient([response]);
    await assert.rejects(client.fetchUsage("gemini"), hasCode("schema_changed"));
  }
});

test("A valid response at the body-size boundary remains readable", async () => {
  const body = fixture("gemini-usage.json");
  const padded = body + " ".repeat(byteLimit - Buffer.byteLength(body));
  const { client } = fixtureClient([new Response(padded)]);
  assert.equal((await client.fetchUsage("gemini")).windows.length, 2);
});

test("Caller cancellation aborts an in-flight request without exposing its reason", { timeout: 1000 }, async () => {
  const controller = new AbortController();
  let observedSignal;
  let requestStarted;
  const started = new Promise(resolve => { requestStarted = resolve; });
  const client = createClient(async (_url, options) => {
    observedSignal = options.signal;
    requestStarted();
    return new Promise((_resolve, reject) => {
      options.signal.addEventListener("abort", () => reject(new Error("private abort reason")), { once: true });
    });
  });
  const pending = client.fetchUsage("gemini", { signal: controller.signal });
  await started;
  controller.abort(new Error("private caller reason"));
  await assert.rejects(pending, error => {
    assert.equal(error.code, "network");
    assert.equal(String(error).includes("private"), false);
    return true;
  });
  assert.equal(observedSignal.aborted, true);
});

test("An already-cancelled refresh sends no provider request", async () => {
  const controller = new AbortController();
  controller.abort();
  for (const provider of ["gemini", "claude"]) {
    const { client, requests } = fixtureClient([]);
    await assert.rejects(client.fetchUsage(provider, { signal: controller.signal }), hasCode("network"));
    assert.equal(requests.length, 0);
  }
});

test("Unexpected fetch errors are sanitized and unsupported providers cannot fetch", async () => {
  const failed = fixtureClient([new Error("private request diagnostics")]);
  await assert.rejects(failed.client.fetchUsage("gemini"), error => {
    assert.equal(error.code, "network");
    assert.equal(String(error).includes("private"), false);
    return true;
  });
  for (const provider of ["codex", "__proto__", "constructor", null]) {
    const { client, requests } = fixtureClient([]);
    await assert.rejects(client.fetchUsage(provider));
    assert.equal(requests.length, 0);
  }
});
