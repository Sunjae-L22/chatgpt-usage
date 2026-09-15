# v0.1.0 verification

Verified on 2026-09-15. These are development checks, not claims of production adoption.

The repository's [initial GitHub Actions run](https://github.com/Sunjae-L22/chatgpt-usage/actions/runs/34976462549) also passed build, all 20 assertions, bundle creation, and signature verification on the hosted macOS runner.

## Environment

- macOS 26.6, Apple Silicon (arm64)
- Apple Swift 6.3.3, direct `swiftc` build in Swift 5 language mode
- Codex CLI 0.154.0-alpha.6.2, from the installed Mac desktop application
- Deployment target: macOS 14. macOS 14/15 and Intel execution have not been tested locally.

## Automated checks

`make test` runs 20 assertions, including:

- Weekly in `primary`, with `secondary: null`.
- Five-hour and weekly windows together, identified by actual duration.
- Multi-bucket preference and legacy fallback.
- Missing values stay unknown; remaining quota is clamped to 0–100.
- A reset in the past does not create fresh quota or a pacing estimate.
- Daily pacing arithmetic and inconsistent-window rejection.
- Invalid explicit executable paths fail without silently falling back.
- A fake subprocess exercises the initialization handshake, split response, notifications, sanitized errors, deadline, and early exit.

The fake subprocess checks use synthetic data. `make bundle` builds a native app, and `codesign --verify --strict` checks its ad-hoc signature. An ad-hoc signature is not Apple notarization.

## Live and visual checks

- The app's own `--check` command fetched real account quota data through `account/rateLimits/read`.
- The live UI displayed a weekly-only core bucket and a separate bucket containing both five-hour and weekly limits.
- Bucket selection, Korean/English switching, settings disclosure, and manual refresh were exercised through the native UI.
- Korean and English sample-data views were rendered and visually inspected for clipping and readable labels. The live window was separately inspected.
- A launch-time repeated-update problem in a SwiftUI menu-bar label was detected during runtime inspection. Replacing that label's TimelineView with an ordinary label and a 30-second model timer resolved the observed loop; a later idle process sample reported 0.0% CPU. This is a point observation, not a battery-life benchmark.

Public images are generated from sample data, not real account payloads.

## Not yet verified

- End-to-end login-item behavior across logout/reboot.
- Every retail plan, enterprise environment, or future server payload.
- Intel runtime, macOS 14/15 runtime, VoiceOver user evaluation, long-duration sleep/wake behavior, or battery impact.
- Apple Developer ID signing and notarization.

The Swift Package manifest is supplied for editors, but the local machine's PackageDescription module and library were inconsistent. The verified build path is the checked-in direct compiler scripts (`make test`, `make bundle`), which do not modify the system toolchain.
