# AI Usage 0.3.0 beta verification

Checked on 2026-10-17, Apple Silicon macOS. Minimum deployment target: macOS 14. Compatibility with every macOS 14+ release has not been established.

## Automated checks

`make test` passed **116 checks**:

| Area | Checks |
|---|---:|
| Existing Codex protocol, discovery, windows, and pacing | 30 |
| Multi-provider normalization, timestamp units, and validation | 12 |
| Claude protocol/parser, passive requests, timeout/process cleanup | 17 |
| Local HTTP parser, authentication, CORS, body limits | 23 |
| Browser parsers, transport projection, permissions, failure states | 16 |
| Native popup layout, stale-state pacing, bridge validation | 18 |

[Raw test output](verification/0.3-tests.txt). Fixtures contain synthetic quota data. They do not establish authenticated browser compatibility.

Additional actual socket checks passed: loopback-only binding; authenticated health; unauthenticated rejection; ordinary website-origin rejection; extension preflight; valid update delivery on MainActor; invalid provider object returns HTTP 422 without an update callback.

## Build and UI

- `make bundle`: successful Apple Silicon app bundle, version 0.3.0, build 5.
- `codesign --verify --strict`: passes ad-hoc signature verification. This is not Apple notarization.
- Korean/English sample renders reviewed; English dates use English locale.
- Six sample windows across three providers fit in a 460×679pt panel. Smaller displays scroll.
- Regression checks confirm a zero-height menu host proposal cannot collapse the panel to a thin strip.
- The menu label uses the store's clock; it does not host a continuously updating TimelineView.

## Live account checks

- **Codex:** a real `account/rateLimits/read` succeeded through the installed desktop CLI; actual weekly-only response appeared in the running app. No model prompt was sent.
- **Claude Code:** installed CLI 2.1.296 accepted the passive initialization and usage request, but returned `rate_limits: null` for this account. The app shows unavailable and offers browser fallback. No model inference was reported.
- **Claude browser:** user loaded and paired the extension. Both session and weekly usage arrived in the running native app and matched the official Claude usage page after converting used to remaining percentages. Reset countdowns matched the official reset times.
- **Gemini browser:** the signed-in usage tab was reloaded after extension installation. Both known windows arrived in the native app. Displayed remaining values matched the official page after used/remaining conversion and its integer rounding; genuine fractional weekly data appeared with one decimal. Reset countdowns matched the official reset times.
- **Combined UI:** all three real providers were visible together in the running app, with independent observation times and window counts. This is one Mac/account combination, not broad compatibility certification.

No personal account payloads, credentials, or real-account screenshots are included in this repository. Demo images remain visibly labeled DEMO.

## Remaining release gates

- Test clean installation on another Mac/account.
- Decide browser-extension store distribution and Apple signing/notarization before recommending a frictionless public install.
- Multiple Claude organizations currently produce an explicit unsupported-selection message.
- Browser collection requires Chrome and a signed-in service tab. Private web endpoint changes can require adapter updates.
- Windows remains future work.
