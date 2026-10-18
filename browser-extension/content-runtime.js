(function () {
  "use strict";
  const failureCodes = new Set(["auth_required", "rate_limited", "schema_changed", "select_account", "network"]);
  async function getText(url) {
    const response = await fetch(url, { credentials: "include", cache: "no-store",
      headers: { Accept: "application/json" }, signal: AbortSignal.timeout(15000) });
    if (response.status === 401 || response.status === 403) throw { code: "auth_required" };
    if (response.status === 429) throw { code: "rate_limited" };
    if (!response.ok) throw { code: "network" };
    if (Number(response.headers.get("content-length")) > 2 * 1024 * 1024) throw { code: "schema_changed" };
    const text = await response.text();
    if (text.length > 2 * 1024 * 1024) throw { code: "schema_changed" };
    return text;
  }
  globalThis.AIUsageContent = { getText, start(provider, fetchUsage) {
    let running = false;
    async function read(requestId) {
      if (running) return { ok: false, status: "busy" };
      running = true;
      let payload;
      try { payload = await fetchUsage(); }
      catch (error) { payload = { provider, error: failureCodes.has(error?.code) ? error.code : "network" }; }
      try { return await chrome.runtime.sendMessage({ type: "usage", payload, requestId }); }
      catch { return { ok: false }; /* Extension may have been reloaded. */ }
      finally { running = false; }
    }
    chrome.runtime.onMessage.addListener((message, sender, respond) => {
      if (sender.id !== chrome.runtime.id || message?.type !== "refresh" || message.provider !== provider ||
          typeof message.requestId !== "string" || !/^[A-Za-z0-9-]{16,80}$/.test(message.requestId)) return;
      read(message.requestId).then(respond);
      return true;
    });
    chrome.runtime.sendMessage({ type: "provider-ready", provider }).catch(() => {});
  } };
})();
