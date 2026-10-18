# Connecting browser usage

AI Usage combines the installed Codex client, an optional Claude Code connection, and a Chrome extension. The extension reads Claude and Gemini quota responses using your existing browser sign-in. It sends a small quota summary to the app on the same Mac.

Gemini here means the Gemini web/app account quota shown on its usage page. Gemini CLI or Antigravity coding quota is a different source and is not substituted for that account quota. The web adapters use the services' current website endpoints, which can change; they are not a promise of a stable public usage API.

## Setup

1. Start AI Usage and open **Connections** from its settings button.
2. Click **Reveal extension** to locate the bundled `browser-extension` folder.
3. Open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**, and select that folder.
4. In AI Usage, click **Copy pairing key**. Open the extension popup, paste the key, and save it.
5. Open [Claude usage](https://claude.ai/settings/usage) and [Gemini usage](https://gemini.google.com/usage), and sign in with the accounts you want to monitor. If background requests are blocked by browser policy, reload a signed-in service tab once to enable content-script fallback.
6. Use **Refresh both** in the extension. Once signed in, service tabs may close; keep Chrome running for automatic updates.

The local app refresh button refreshes local clients. The extension has its own manual refresh and five-minute alarm. Its worker requests fixed quota endpoints directly using the existing browser session, so closing or suspending a service tab no longer stops polling. Device sleep, Chrome being closed, or a signed-out session can delay new readings; the app marks readings stale after ten minutes or a reported error.

At each refresh with service tabs open, the extension selects an active tab first, then the most recently accessed tab. Switching between already-open tabs is reflected on the next refresh. Gemini remembers only the numeric Google account index from that tab's URL for later background requests; without a prior selection it uses the default account. An open signed-in tab can act as a fallback if browser policies prevent a background request. Fallback has a deadline and does not activate or reload your tabs. Claude accounts with multiple organizations are not automatically guessed: the extension reports that organization selection is not supported yet. A supported Claude Code installation can still provide Claude readings without that browser connection.

## What the connection carries

The app listens only on `127.0.0.1:49627`. It does not listen on Wi-Fi or other network interfaces. A persistent pairing key is generated locally from 32 random bytes; it is unrelated to any OpenAI, Anthropic, or Google credential.

The extension forwards an allowlisted object with the provider, supported quota windows, usage percentages, reset times, observation time, and a fixed source label. It strips other response fields. Names, email addresses, organization identifiers, cookies, access tokens, conversation content, and raw service responses are not forwarded. Browser plan names are currently left unknown.

```json
{
  "provider": "gemini",
  "plan": null,
  "windows": [{
    "id": "GXU_WEEKLY",
    "label": null,
    "usedPercent": 42.5,
    "windowDurationMins": 10080,
    "resetsAt": 1800000000
  }],
  "updatedAt": 1799700000,
  "source": "Gemini web"
}
```

This is a protocol illustration, not a current account reading. Both timestamps use Unix seconds. Missing reset times remain `null`. Known provider window identifiers supply their documented duration; unknown periods are not invented. Gemini fractions are converted to percent, while Claude utilization is already a percent.

Errors use only a provider and one fixed code: `auth_required`, `rate_limited`, `select_account`, `schema_changed`, or `network`. The native app displays its own explanation rather than server error text.

## Local HTTP contract

| Route | Purpose | Authentication |
|---|---|---|
| `GET /v1/health` | Confirm the paired app is available | `Authorization: Bearer <pairing key>` |
| `POST /v1/usage` | Submit a quota snapshot or known status error | Same pairing header |
| `OPTIONS` for either route | Browser preflight | Valid extension origin; no pairing header needed |

Cross-origin access is allowed only for origins matching `chrome-extension://[a-p]{32}`. Native diagnostic requests may omit `Origin`, but still need the pairing header. Requests from ordinary website origins are rejected.

POST requires `Content-Type: application/json`, a `Content-Length`, and a JSON object. Headers are limited to 8 KiB and bodies to 64 KiB. Duplicate headers, transfer encoding, extra body bytes, and unsupported methods/routes are rejected. Connections have a ten-second deadline.

The app validates provider data before acknowledging it. HTTP `200` means it accepted the payload; `204` is a successful preflight, `401` means pairing failed, and `422` means the JSON object does not match a supported provider payload. Old snapshots cannot replace a newer reading. Each service has independent freshness and error state.

## Reconnect or stop

**New pairing key** in the app immediately invalidates the saved extension key. Copy the replacement into the extension and refresh. **Disconnect** in the extension removes its saved key and stops sending usage. Removing the extension has the same effect. Quota snapshots are not retained across app restarts.

If the app cannot open its local listener, close other running copies and restart it. A browser error does not alter Codex authentication. For implementation and storage details, see [Privacy](PRIVACY.md).
