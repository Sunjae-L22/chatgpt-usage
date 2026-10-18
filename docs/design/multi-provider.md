# Multi-provider desktop direction

Mac first. Name: AI Usage. Extend this repository and retain its existing preferences and Codex integration.

Palette: system window/surface backgrounds; ink #202329, secondary #737982; Codex teal #218678, Claude copper #B96743, Gemini blue #4279D8. Native SF typography: 24pt title, 16pt service name, 12pt quota labels, 11pt status. Standard numerals with tabular alignment for values; no decorative gradients or simulated brand logos.

A 460pt menu panel presents three stacked service rows. Each row shares the same label, remaining quota, reset time and pace-marker alignment, so all services can be compared without switching tabs. Two main windows remain visible per service; extra named limits expand deliberately. Settings stay outside the main quota grid. Native light/dark colors and a measured scroll viewport preserve menu usability on shorter displays.

    AI Usage                         refresh  settings
    Remaining quota / 남은 한도
    Codex                      live / updated time
    Weekly                  [quota---|---] 58%
    resets in 3d12h          elapsed 50% / spare 8pp
    Claude                     live / connect
    Session                 [quota---|---] 74%
    Weekly                  [quota---|---] 45%
    Gemini                     live / connect
    5 hours                 [quota---|---] 81%
    Weekly                  [quota---|---] 62%
    Updated time                          open window

Review against brief: consistent rows are intentional comparison structure, not independent marketing cards. Color identifies provider only. Pace markers are the single distinctive visual. Avoid inaccurate combined quotas, fabricated unconnected values, hard-coded retail plan assumptions and unlabeled demo data. Native acquisition methods must match actual provider product scope.

## Compact menu indicator

The selected menu-bar design uses a fixed 24 × 18pt image with three 5 × 14pt vertical tracks, in Codex → Claude → Gemini order. Fill grows upward with remaining quota. Teal, copper and blue match the provider identities, with separate light/dark colors for small marks. This is a glanceable approximation; exact values and reset times remain in the existing click-to-open panel. The menu no longer grows with percentages or connection status.

Each provider keeps the existing headline selection: prefer its weekly window, otherwise its first reported window. The tooltip and accessibility summary name that window. Values from different providers are never combined. Stale, failed, expired or missing readings use neutral broken marks; genuine 0% remains a solid empty track. Refreshing an otherwise fresh reading does not cause flicker. No new animation or rotating labels.

Windows phase: keep normalization/parsing separate from macOS UI and authentication so a later Windows host can reuse the data contract. Windows is not part of this release.

## Selected card polish

The user selected the soft provider-tinted cards at 12% tint. Blend that fill over an opaque neutral card (#FFFFFF light / #26272A dark), leaving text fully opaque. Provider light/dark accents: Codex #187B69 / #55BFA8, Claude #A65734 / #D9936E, Gemini #356CC8 / #78A1EF. Keep native system canvas and semantic text colors.

Retain the 460pt measured panel and stacked quota windows. Use SF 20pt for the app title, 16pt for providers, 22pt for percentage numerals, 13pt for the percent sign, and 11pt for reset/status details. Remove the introductory tagline; keep per-provider update times. Explain quota fill and time-left marker together below the cards, once. Warning text and symbols distinguish stale data even on Claude's copper tint. Keep the menu icon, acquisition, percentages, timing calculations, and settings behavior unchanged.
