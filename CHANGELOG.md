# Changelog

## 0.3.0 beta — compact menu update

- Add provider-colored card backgrounds at 12% tint, with light/dark palettes.
- Refine the title, percentage typography and reset labels; add a shared legend for quota fill and the time-left marker.
- Replace the three text percentages with a fixed-size, three-bar menu icon in Codex / Claude / Gemini order.
- Keep exact remaining quota, reset countdowns, and pace markers in the existing click-to-open panel.
- Distinguish missing, stale, failed and expired readings from a real 0%; add window-aware English/Korean tooltip and accessibility text.

## 0.2.1 — 2026-09-30

- Restore desktop Codex detection after its bundled CLI moved into `Resources/codex-cli`.
- Support the new CLI launcher and packaged executable while preserving legacy paths and explicit overrides.
- Add four bundle-discovery regression checks.

## 0.2.0 — 2026-09-18

- Add a time-remaining marker to the quota bar, with elapsed and remaining window percentages.
- Compare remaining quota with an even-use pace in percentage points.
- Hide the pace marker for stale readings and missing, expired, or inconsistent timing.
- Add six arithmetic checks and refresh Korean/English sample screenshots.

## 0.1.1 — 2026-09-16

- Fix the menu-bar popup appearing as a thin horizontal strip. The popup now has an explicit initial height, then fits its content and scrolls when needed.
- Bound the popup height to the display containing the menu.
- Add nine native SwiftUI layout checks covering first layout, settings, long content, and loading/disconnected states.

## 0.1.0 — 2026-09-15

- Initial experimental release for Codex subscription limits and reset times.
