(function (root) {
  "use strict";
  class UsageError extends Error { constructor(code) { super(code); this.code = code; } }
  const definitions = [
    ["five_hour", null, 300], ["seven_day", null, 10080],
    ["seven_day_sonnet", "Sonnet", 10080], ["seven_day_opus", "Opus", 10080]
  ];
  function json(text) {
    if (typeof text !== "string") throw new UsageError("schema_changed");
    if (text.trimStart().startsWith("<")) throw new UsageError("auth_required");
    try { return JSON.parse(text); } catch { throw new UsageError("schema_changed"); }
  }
  function organization(text) {
    const organizations = json(text);
    if (!Array.isArray(organizations)) throw new UsageError("schema_changed");
    if (organizations.length === 0) throw new UsageError("auth_required");
    // An account may contain personal and work organizations. Never guess which
    // subscription belongs in the menu bar, and never forward organization IDs.
    if (organizations.length !== 1) throw new UsageError("select_account");
    const id = organizations[0]?.uuid;
    if (typeof id !== "string" || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(id)) {
      throw new UsageError("schema_changed");
    }
    return id;
  }
  function parse(text, now = Date.now() / 1000) {
    const response = json(text);
    if (response === null || typeof response !== "object" || Array.isArray(response)) throw new UsageError("schema_changed");
    const windows = [];
    for (const [id, label, minutes] of definitions) {
      const item = response[id];
      if (item === undefined || item === null) continue;
      if (typeof item.utilization !== "number" || !Number.isFinite(item.utilization) ||
          item.utilization < 0 || item.utilization > 100) throw new UsageError("schema_changed");
      const rawReset = item.resets_at;
      const timestamp = typeof rawReset === "string" && /^\d{4}-\d{2}-\d{2}T/.test(rawReset) ? Date.parse(rawReset) : NaN;
      windows.push({ id, label, usedPercent: item.utilization, windowDurationMins: minutes,
        resetsAt: Number.isFinite(timestamp) && timestamp > 0 ? timestamp / 1000 : null });
    }
    if (windows.length === 0 || !Number.isFinite(now)) throw new UsageError("schema_changed");
    return { provider: "claude", plan: null, windows, updatedAt: now, source: "Claude web" };
  }
  const api = { parse, organization, UsageError };
  root.AIUsageClaude = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(globalThis);
