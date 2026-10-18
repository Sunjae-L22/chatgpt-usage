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

## Compact menu update — 2026-10-18

- `make test` passed **145 checks**: the previous 116 plus 29 menu-state, accessibility and raster-render checks. [Output](verification/mini-bars-tests.txt).
- The 24×18pt icon keeps Codex / Claude / Gemini positions in both appearances at 1× and 2× scale. Tests distinguish fresh 0% from unknown/stale marks, check full/half fill proportions, preserve a fresh value during refresh, and reject expired or failed values as current.
- The existing popup geometry checks still pass, including its first zero-height host proposal and short-display scrolling. Popup layout and click routing were not changed.
- Version 0.3.0, build 6 was bundled, ad-hoc signature verified, and installed over the running local app. Installed executable SHA-256 matched the built bundle. The previous installed bundle was backed up locally.
- All three providers repopulated in the running native detail window after restart; quota values and reset countdowns were visible. Existing extension pairing was retained.
- The user confirmed that all three mini bars appear in the actual menu bar and clicking opens the detail panel correctly. This complements the native detail-window and automated layout checks above; the UI tool cannot directly select the status-item icon.

## Tinted card polish — 2026-10-18

- The selected design uses a 12% provider-color overlay on an opaque neutral card, with separate light/dark palettes. Only presentation changed: quota collection, precision, reset timestamps, pacing math, and the three-bar menu indicator are unchanged.
- The existing **145-check suite** passes. No new tests were added for these reversible visual changes. [Output](verification/tinted-cards-tests.txt).
- Korean/English dark/light sample renders were reviewed at 920×1420 pixels (460×710pt for six sample windows). Percentages, resets, plans and legend fit without clipping. The time marker retains a thin contrast edge; secondary text uses explicit theme-aware colors.
- Version 0.3.0, build 7 was bundled, signature-verified and installed after backing up the previous app. The installed executable matches the built bundle. The running native detail window shows all three real providers with the new card backgrounds, remaining quotas and reset countdowns.
- Public preview images contain DEMO data. No live account screenshots are committed.

## Remaining release gates

- Test clean installation on another Mac/account.
- Decide browser-extension store distribution and Apple signing/notarization before recommending a frictionless public install.
- Multiple Claude organizations currently produce an explicit unsupported-selection message.
- Browser collection requires Chrome and a signed-in service tab. Private web endpoint changes can require adapter updates.
- Windows remains future work.
