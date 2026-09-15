# Security and privacy

ChatGPT Usage delegates authentication and quota requests to the installed Codex executable. It does not directly open credential files, query Keychain, read browser cookies, or read conversation history. The subprocess receives only initialization and a rate-limit read request; it does not start model turns or redeem reset credits.

The subprocess is closed after each request and has a 20-second response deadline. Errors shown in the UI use fixed messages rather than raw server content. App-server stderr is discarded. Quota snapshots remain in process memory; the app saves language and the optional executable path in UserDefaults.

The chosen Codex binary runs with your user permissions. Select a trusted local installation. This app is not App-Sandboxed because it launches Codex. Codex itself can perform its normal authentication and service requests. Analytics are disabled for the app's subprocess.

Report security concerns through GitHub's private vulnerability reporting if enabled. If unavailable, open a minimal issue asking for a private contact channel without posting exploit details or secrets. Never upload auth.json, access/refresh tokens, browser sessions, or personal account payloads.

The first release is ad-hoc signed and not notarized. Release SHA-256 checksums detect corruption; they are not a substitute for Apple notarization or publisher identity verification.
