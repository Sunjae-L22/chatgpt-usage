/* Independently implemented adapter for the Gemini web usage response.
 * Endpoint/schema reference: CodexBar's Gemini web provider (MIT), see README.
 * This file is both a classic Chrome content script and a Node-testable module.
 */
(function (root) {
  "use strict";
  class UsageError extends Error {
    constructor(code) { super(code); this.code = code; }
  }
  const durations = Object.freeze({ GXU_FIVE_HOURLY: 300, GXU_WEEKLY: 10080 });
  const isRecord = value => value !== null && typeof value === "object" && !Array.isArray(value);
  function resetSeconds(value) {
    if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T/.test(value)) return null;
    const milliseconds = Date.parse(value);
    return Number.isFinite(milliseconds) && milliseconds > 0 ? milliseconds / 1000 : null;
  }
  function parse(text, now = Date.now() / 1000) {
    if (typeof text !== "string") throw new UsageError("schema_changed");
    if (text.trimStart().startsWith("<")) throw new UsageError("auth_required");
    let response;
    try { response = JSON.parse(text.trim().replace(/^\)\]\}'\s*/, "")); }
    catch { throw new UsageError("schema_changed"); }
    if (!Array.isArray(response)) throw new UsageError("schema_changed");
    const item = response.find(item => isRecord(item?.data) && Object.hasOwn(item.data, "viewer"));
    if (item?.data.viewer === null) throw new UsageError("auth_required");
    const pools = item?.data.viewer?.rpcs?.getUsageInfo?.pools;
    if (!Array.isArray(pools)) throw new UsageError("schema_changed");
    const windows = [];
    for (const [id, minutes] of Object.entries(durations)) {
      const matching = pools.filter(pool => isRecord(pool) && pool.poolType === id);
      if (matching.length === 0) continue;
      if (matching.length !== 1) throw new UsageError("schema_changed");
      const pool = matching[0];
      // The upstream value is a fraction, not an integer percent. Missing values
      // never mean zero. Reject a changed unit instead of silently clamping it.
      if (typeof pool.percentageUsed !== "number" || !Number.isFinite(pool.percentageUsed) ||
          pool.percentageUsed < 0 || pool.percentageUsed > 1) throw new UsageError("schema_changed");
      windows.push({ id, label: null, usedPercent: pool.percentageUsed * 100,
        windowDurationMins: minutes, resetsAt: resetSeconds(pool.gxu?.windowRefreshesAt) });
    }
    if (windows.length === 0 || !Number.isFinite(now)) throw new UsageError("schema_changed");
    return { provider: "gemini", plan: null, windows, updatedAt: now, source: "Gemini web" };
  }
  function url(pageURL = "https://gemini.google.com/usage") {
    const endpoint = new URL("https://gemini.google.com/_/BardChatUi/graphql/schemas/GEMINI_WEB_GRAPHQL/executeQuery");
    endpoint.searchParams.set("query_signature", "2/dWbCvkVB0X16r9NPnxifeOAAqdCqMf0xeWvau9yPy7g=");
    endpoint.searchParams.set("variables", JSON.stringify({
      g1Request: { entrypoints: ["GEMINI_USAGE_SETTINGS_UPGRADE_BANNER"] },
      workspaceRequest: { recommendationsForSurfaceRequests: [] }
    }));
    const page = new URL(pageURL);
    // Preserve an explicit Google account index; never send an email identifier.
    const index = page.pathname.match(/^\/u\/(\d+)(?:\/|$)/)?.[1] ?? page.searchParams.get("authuser");
    if (index !== null && index !== undefined && /^\d{1,3}$/.test(index)) endpoint.searchParams.set("authuser", index);
    return endpoint.href;
  }
  const api = { parse, url, UsageError };
  root.AIUsageGemini = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(globalThis);
