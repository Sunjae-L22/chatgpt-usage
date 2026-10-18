"use strict";
const $ = id => document.getElementById(id);
const statuses = {
  not_configured: "Pair with AI Usage to start.", waiting_for_tab: "Open usage and sign in to connect.",
  fetching: "Reading your quota…", reload_tab: "Reload this service’s tab once, then refresh.",
  bridge_unavailable: "Open AI Usage on this Mac, then refresh.", pairing_rejected: "Pairing code rejected. Copy a fresh code from AI Usage.",
  bridge_error: "The app could not accept this update. Update AI Usage.", auth_required: "Open usage and sign in again. If already signed in, keep that tab open for browser fallback.",
  rate_limited: "Too many requests. The next refresh will retry.", schema_changed: "The service’s usage response changed or has no supported quota. An adapter update may be needed.",
  network: "Could not read usage. Check your connection and retry.",
  select_account: "Several Claude organizations were found. Automatic selection is not supported yet."
};
async function send(message) { return chrome.runtime.sendMessage(message); }
async function render() {
  const state = await send({ type: "status" });
  const delivered = [state?.claude, state?.gemini].some(item => item?.status === "delivered");
  $("connection").textContent = delivered && state?.configured ? "Connected" : state?.configured ? "Code saved" : "Not paired";
  $("token").placeholder = state?.configured ? "Code saved · paste to replace" : "Paste code";
  $("schedule").textContent = !state?.configured ? "Automatic refresh starts after pairing."
    : Number.isFinite(state.nextRefreshAt)
      ? `Next automatic check around ${new Date(state.nextRefreshAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`
      : "Automatic refresh schedule is being restored.";
  for (const provider of ["claude", "gemini"]) {
    const item = state?.[provider];
    $(provider + "-status").textContent = item?.status === "delivered"
      ? `Sent to AI Usage at ${new Date(item.deliveredAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`
      : statuses[item?.status] || (state?.configured ? "Waiting for the next automatic check." : statuses.not_configured);
  }
}
async function busy(id, action) {
  $(id).disabled = true;
  try { await action(); } catch { $("feedback").textContent = "Extension unavailable. Close and reopen this panel."; }
  finally { $(id).disabled = false; await render(); }
}
$("pair-form").addEventListener("submit", event => {
  event.preventDefault();
  busy("save", async () => {
    const result = await send({ type: "save-token", token: $("token").value });
    $("feedback").textContent = result?.ok ? "Paired. Open usage for each service to connect." : "Paste the complete pairing code from AI Usage.";
    if (result?.ok) $("token").value = "";
  });
});
$("refresh").addEventListener("click", () => busy("refresh", () => send({ type: "refresh-all" })));
$("disconnect").addEventListener("click", () => busy("disconnect", async () => {
  await send({ type: "disconnect" }); $("feedback").textContent = "Disconnected. No usage will be sent.";
}));
$("open-claude").addEventListener("click", () => chrome.tabs.create({ url: "https://claude.ai/settings/usage" }));
$("open-gemini").addEventListener("click", () => chrome.tabs.create({ url: "https://gemini.google.com/usage" }));
chrome.storage.onChanged.addListener(render);
render();
