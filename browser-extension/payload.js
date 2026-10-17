(function (root) {
  "use strict";
  const knownWindows = {
    gemini: { GXU_FIVE_HOURLY: [300, null], GXU_WEEKLY: [10080, null] },
    claude: { five_hour: [300, null], seven_day: [10080, null], seven_day_sonnet: [10080, "Sonnet"], seven_day_opus: [10080, "Opus"] }
  };
  const errors = new Set(["auth_required", "rate_limited", "schema_changed", "select_account", "network"]);
  function sanitize(payload, now = Date.now() / 1000) {
    if (!payload || !Object.hasOwn(knownWindows, payload.provider)) throw new Error("invalid_payload");
    const definitions = knownWindows[payload.provider];
    if (errors.has(payload.error)) return { provider: payload.provider, error: payload.error };
    if (!Array.isArray(payload.windows) || payload.windows.length === 0 || payload.windows.length > Object.keys(definitions).length) throw new Error("invalid_payload");
    const seen = new Set();
    const windows = payload.windows.map(item => {
      if (!item || !Object.hasOwn(definitions, item.id)) throw new Error("invalid_payload");
      const definition = definitions[item.id];
      if (seen.has(item.id) || typeof item.usedPercent !== "number" ||
          !Number.isFinite(item.usedPercent) || item.usedPercent < 0 || item.usedPercent > 100 ||
          item.windowDurationMins !== definition[0]) throw new Error("invalid_payload");
      seen.add(item.id);
      if (item.resetsAt !== null && item.resetsAt !== undefined &&
          (typeof item.resetsAt !== "number" || !Number.isFinite(item.resetsAt) || item.resetsAt <= 0)) throw new Error("invalid_payload");
      return { id: item.id, label: definition[1], usedPercent: item.usedPercent,
        windowDurationMins: definition[0], resetsAt: item.resetsAt ?? null };
    });
    if (typeof payload.updatedAt !== "number" || !Number.isFinite(payload.updatedAt) ||
        payload.updatedAt > now + 60 || payload.updatedAt < now - 120) throw new Error("invalid_payload");
    // Build a new object field by field: nothing else in the upstream response,
    // page, or runtime message can accidentally travel to the native app.
    return { provider: payload.provider, plan: null, windows, updatedAt: payload.updatedAt,
      source: payload.provider === "gemini" ? "Gemini web" : "Claude web" };
  }
  const api = { sanitize };
  root.AIUsagePayload = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(globalThis);
