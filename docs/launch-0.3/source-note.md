# Editorial evidence and publication state

This file is review metadata, not part of the blog body. No social post or Tistory edit was made while preparing this package.

## Reader question and follow-up decision

Reader question: How can a Mac user compare the remaining subscription quotas and reset times of Codex, Claude, and Gemini without confusing the different products' limits?

The earlier Codex-only post is explicitly recorded at https://it-study-2002.tistory.com/entry/chatgpt-usage-codex-macos . The current work adds a multi-provider comparison screen, per-provider connection methods, and privacy-aware browser transport. Those are enough new questions and implementation work for a follow-up post instead of silently rewriting the original. The public URL was supplied in project history; a fresh web read failed, so this package does not claim a newly verified comparison with every sentence of that original post.

## User-reported experience

- Previously used Claude Usage Tracker, then created and used ChatGPT Usage for Codex on Mac.
- Currently uses ChatGPT/Codex, Claude, and Gemini's new Argon model.
- Wants all three usages visible together in a clean Mac app, with Windows considered after Mac works.
- Previously requested the time-remaining pace line.
- Wants GitHub, blog, and SNS materials; no audience, stars, downloads, or adoption outcomes were supplied.

## Repository evidence reviewed

- README.md and browser-extension/README.md define current product scope and setup.
- docs/design/multi-provider.md defines the aligned three-provider layout and time marker.
- Sources/UsageCore/Provider.swift holds distinct provider snapshots and actual windows; no invented combined quota.
- Sources/UsageCore/ClaudeClient.swift sends initialize/get_usage control requests only, with skip_behaviors true; does not directly read service credentials.
- browser-extension source and README describe same-origin quota queries, allowlisted loopback payloads, no cookies permission, no cloud relay, and app pairing.
- docs/ACKNOWLEDGMENTS.md records CodexBar's protocol research contribution.

## Verification boundary at drafting time

- The completed automated suite passed 116 checks, covering parsing, subprocess behavior, transport validation, and display-related cases. The count is a check total, not a claim about real-account coverage.
- Live Claude Code 2.1.296 initialized and accepted get_usage; rate_limits_available was true but rate_limits was null. Session model usage was empty and cost zero. The source returns unavailable rather than manufacturing quota.
- The author installed and paired the extension, and live connections for Codex, Claude, and Gemini were verified on the author’s Mac. The running native app’s Claude/Gemini quota and reset displays were compared with their signed-in official usage pages. This does not establish compatibility with other accounts or Mac installations. No personal values, reset times, account identifiers, or live account screenshots are included in this package.
- Three-service screenshot is sample data and must retain its DEMO label. It cannot substantiate live connections.
- Apple notarization and Chrome Web Store publication have not occurred. Windows implementation has not occurred.
- No social or Tistory publication occurred. Technical and visual review are complete; the package is ready_for_user_authoring, not published.

## Source roles

- https://code.claude.com/docs/en/commands — official Claude usage-command context; not a promise that the experimental get_usage schema is a stable public API.
- https://github.com/anthropics/claude-agent-sdk-typescript/blob/main/CHANGELOG.md — public SDK history supporting structured usage research.
- https://support.google.com/gemini/answer/16275805?hl=en — official consumer Gemini app usage limits.
- https://blog.google/innovation-and-ai/products/gemini-app/gemini-4-argon-availability/ — official October 2026 Argon availability.
- https://github.com/steipete/CodexBar/blob/main/docs/gemini.md — explicit Gemini app versus Gemini CLI versus Antigravity distinction.
- https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Resources/Plugins/gemini-web.ts — published Gemini app usage request and response schema; implementation here is independently authored.
- https://github.com/steipete/CodexBar — established competing project acknowledged; no first/only-product claim.

## Image handoff

The current sample screenshot was copied to img/ai-usage-demo-ko.png and inspected at full size. Its DEMO label, three provider names, percentages, reset labels, and time markers are visible. post.md contains its insertion marker, alt text, and caption. The rendered article was reviewed on desktop and at 390×844 and 360×800 mobile viewports. No clipping or horizontal overflow was found. DEMO and main quota values are legible; the screenshot’s smaller details can be enlarged.

## Draft choices

- Conversational Korean grounded in the user's actual request; implementation help from Codex is acknowledged.
- Source limits and private endpoints described plainly, without hidden claims of reliability.
- SNS reports working connections on the author’s own Mac and keeps the early-beta setup limits explicit; it does not generalize that result to other accounts or devices.
- GitHub points to the feat/multi-provider-usage branch for the current beta source/setup, not the older default-branch version or an unverified release download.
