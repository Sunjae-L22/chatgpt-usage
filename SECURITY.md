# Security

AI Usage reads Codex, Claude, and Gemini quota through installed clients or its browser extension. It does not start model turns, extract upstream login tokens, or copy cookies into the native app. See [data handling](docs/PRIVACY.md) and the [local bridge protocol](docs/BRIDGE.md) for permissions, storage, and trust boundaries.

The app is not App-Sandboxed because it starts local CLI clients. Choose trusted installations. The browser extension can access the two declared service origins; review its source before loading it. Its pairing key allows writing quota summaries to the loopback listener, not access to your provider accounts. The key is local and should not be published.

Report security concerns through GitHub's private vulnerability reporting if enabled. If unavailable, open a minimal issue asking for a private contact channel without exploit details or secrets. Never upload credential files, access/refresh tokens, browser sessions, pairing keys, conversation files, or personal account payloads.

Builds are ad-hoc signed and not notarized. Release SHA-256 checksums detect corruption; they are not a substitute for publisher identity verification. Development source and a passing test run do not guarantee future compatibility with private provider endpoints.
