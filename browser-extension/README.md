# AI Usage browser bridge

A small, unpacked Chrome Manifest V3 extension for the native AI Usage Mac app. It reads the **Gemini app** and **Claude web** quota endpoints from your signed-in tabs. Codex remains connected directly through the local Codex CLI.

This is an early adapter, not a Chrome Web Store release. Its parsers and transport have automated checks; successful tests alone do not establish that your account is connected. The popup must say **Sent to AI Usage**, and the Mac app must show an updated quota.

## Install and pair

1. Open the AI Usage Mac app and enable/open its browser connection in Settings. Copy its pairing code.
2. Open `chrome://extensions`, turn on **Developer mode**, and choose **Load unpacked**. Select this `browser-extension` directory (the folder containing `manifest.json`).
3. Open the extension from Chrome’s puzzle-piece menu, paste the code, and click **Pair**.
4. Use **Open usage** for Claude and Gemini, then sign in normally in those tabs. Keep one tab for each service open. Existing tabs from before installation need one reload.
5. Click **Refresh both**. A successful transfer says **Sent to AI Usage at …** for that service. Pairing alone only says **Code saved** until a quota is successfully transferred.

Refresh runs on tab load and every five minutes while Chrome has a tab open for that service. The native app does not refresh these browser-based providers when Chrome is closed. With several tabs open for a service, the active or most recently accessed tab is used. Explicit numeric Google account indices are preserved; email account selectors are not extracted.

To disconnect, click **Disconnect** in the extension. If the native app rotates its code, copy and pair with the new code. Remove the extension via `chrome://extensions` to remove its local configuration entirely.

## What leaves the browser

Only this allowlisted information is sent to `http://127.0.0.1:49627/v1/usage` on this Mac:

- Provider name, quota window identifiers and labels, actual percentage used, window duration, reset timestamps, and fetch timestamp.
- A small error code when authentication, networking, or the response format fails.

The extension does **not** send cookies, passwords, tokens from the service, conversation content, email addresses, organization identifiers, or raw API responses. It does not read chat messages or request the `cookies` permission. Requests to each service use the existing session through same-origin `fetch` inside an isolated content script. The Mac connection uses a separate pairing code, saved only in `chrome.storage.local` rather than Chrome Sync. No analytics or remote reporting is included.

The only host permissions are Claude, Gemini, and the loopback bridge. The extension can run on conversation pages to perform the quota request, but does not inspect the conversation DOM. Its popup reports sanitized statuses rather than server responses.

## Supported data and limitations

- **Gemini app:** `GXU_FIVE_HOURLY` and `GXU_WEEKLY` pools, when the account supplies them. `percentageUsed` is a fraction, so `0.425` becomes `42.5%`. Gemini CLI and Antigravity quotas are separate products and are not substituted here.
- **Claude web:** `five_hour`, `seven_day`, and optional Sonnet/Opus weekly windows. Currently a Claude account must return exactly one organization. Multiple organizations produce an explicit selection-not-supported status instead of silently showing the wrong subscription.
- Other quota scopes, additional credits, billing, and subscription prices are not inferred. An unknown/missing quota is not presented as zero. Plan labels stay unset because these adapters do not verify a plan name.
- Missing or invalid reset timestamps stay unavailable. Fractional percentages are retained only when the service returns them.
- These are web-app endpoints, not documented public quota APIs. Service changes, login expiry, account differences, or browser policies can break the integration. A changed payload produces an error rather than invented values.
- The Gemini query signature is version-specific. An adapter update may be required when Google changes its usage page.

## Development

```sh
node --test browser-extension/tests/*.test.js
```

Run the command from the repository root. Tests use synthetic fixtures, never saved account responses or credentials. They verify fractional values, authentication errors, changed schemas, unknown scopes, missing resets, organization ambiguity, payload privacy, sender checks, and loopback authorization. Reload the unpacked extension after changing code and reload provider tabs once.

`gemini-parser.js` and `claude-parser.js` normalize responses. `content-runtime.js` runs read-only requests in the provider’s origin. `payload.js` independently validates and reconstructs the outbound fields. `background.js` forwards those summaries to the native app and manages the refresh alarm.

## Protocol references and attribution

The adapters are independently implemented. Public endpoint/schema references came from [CodexBar](https://github.com/steipete/CodexBar), licensed under [MIT](https://github.com/steipete/CodexBar/blob/main/LICENSE):

- [Gemini web provider](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Resources/Plugins/gemini-web.ts) and [Gemini documentation](https://github.com/steipete/CodexBar/blob/main/docs/gemini.md).
- [Claude web API fetcher](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebAPIFetcher.swift).

No CodexBar browser-cookie extraction code is used. This bridge deliberately uses the existing browser session in place.
