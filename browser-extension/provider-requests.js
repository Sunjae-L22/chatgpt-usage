(function (root) {
  "use strict";
  const gemini = root.AIUsageGemini || (typeof require === "function" ? require("./gemini-parser.js") : null);
  const claude = root.AIUsageClaude || (typeof require === "function" ? require("./claude-parser.js") : null);
  const codes = new Set(["auth_required", "rate_limited", "schema_changed", "select_account", "network"]);
  const maxBytes = 2 * 1024 * 1024;
  const failure = code => Object.assign(new Error(code), { code });
  function createClient(fetchImpl) {
    async function getText(url, signal) {
      const response = await fetchImpl(url, { credentials: "include", cache: "no-store", redirect: "error",
        headers: { Accept: "application/json" }, signal });
      if (response.status === 401 || response.status === 403) throw failure("auth_required");
      if (response.status === 429) throw failure("rate_limited");
      if (!response.ok) throw failure("network");
      if (Number(response.headers.get("content-length")) > maxBytes) throw failure("schema_changed");
      if (response.body?.getReader) {
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let size = 0, result = "";
        try {
          while (true) {
            if (signal.aborted) throw failure("network");
            const { done, value } = await reader.read();
            if (done) break;
            size += value.byteLength;
            if (size > maxBytes) { await reader.cancel(); throw failure("schema_changed"); }
            result += decoder.decode(value, { stream: true });
          }
          return result + decoder.decode();
        } finally { reader.releaseLock(); }
      }
      const text = await response.text();
      if (new TextEncoder().encode(text).byteLength > maxBytes) throw failure("schema_changed");
      return text;
    }
    async function fetchUsage(provider, { accountIndex = null, signal } = {}) {
      if (provider !== "gemini" && provider !== "claude") throw failure("schema_changed");
      const controller = new AbortController();
      const abort = () => controller.abort();
      if (signal?.aborted) abort();
      else signal?.addEventListener("abort", abort, { once: true });
      const timeout = setTimeout(abort, 20000);
      try {
        if (controller.signal.aborted) throw failure("network");
        if (provider === "gemini") {
          const page = new URL("https://gemini.google.com/usage");
          if (typeof accountIndex === "string" && /^\d{1,3}$/.test(accountIndex)) page.searchParams.set("authuser", accountIndex);
          return gemini.parse(await getText(gemini.url(page.href), controller.signal));
        }
        const organization = claude.organization(await getText("https://claude.ai/api/organizations", controller.signal));
        return claude.parse(await getText(`https://claude.ai/api/organizations/${organization}/usage`, controller.signal));
      } catch (error) { throw failure(codes.has(error?.code) ? error.code : "network"); }
      finally { clearTimeout(timeout); signal?.removeEventListener("abort", abort); }
    }
    return { fetchUsage };
  }
  const api = { createClient, fetchUsage: (...args) => createClient(root.fetch.bind(root)).fetchUsage(...args) };
  root.AIUsageRequests = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(globalThis);
