import AppKit
import SwiftUI
import UsageCore

@MainActor func runMenuBarChecks(_ check: (Bool, String) -> Void) throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func window(_ used: Double?, reset: Double? = nil, minutes: Int = 10080) -> ProviderWindow {
        ProviderWindow(id: "\(minutes)", usedPercent: used, windowDurationMins: minutes,
                       resetsAt: reset ?? now.addingTimeInterval(Double(minutes) * 30).timeIntervalSince1970)
    }
    func state(_ provider: ProviderID, windows: [ProviderWindow], age: TimeInterval = 0,
               error: String? = nil, loading: Bool = false) -> ProviderState {
        ProviderState(snapshot: ProviderSnapshot(provider: provider, plan: nil, windows: windows,
                                               updatedAt: now.addingTimeInterval(-age), source: "Test"),
                      error: error, loading: loading)
    }
    func reading(_ provider: ProviderID, _ used: Double?) -> MenuBarReading {
        MenuBarReading(provider: provider, state: state(provider, windows: [window(used)]), now: now)
    }
    let full = reading(.codex, 0)
    let empty = reading(.claude, 100)
    let half = reading(.gemini, 50)
    check(full.status == .available && full.remaining == 100, "Fresh zero usage means a full remaining quota bar")
    check(empty.status == .available && empty.remaining == 0, "A real zero remaining quota stays available rather than unknown")
    check(MenuBarReading(provider: .codex, state: ProviderState(), now: now).status == .unavailable,
          "Missing provider data is unavailable rather than a zero quota")
    check(reading(.codex, nil).status == .unavailable, "Missing percentage is unavailable")
    check(reading(.codex, .nan).status == .unavailable, "Nonfinite percentage cannot become a colored bar")
    let boundary = state(.codex, windows: [window(0)], age: 600)
    check(MenuBarReading(provider: .codex, state: boundary, now: now).status == .available &&
          MenuBarReading(provider: .codex, state: boundary, now: now.addingTimeInterval(0.01)).status == .refreshNeeded,
          "Freshness expires after the ten-minute boundary")
    let expired = MenuBarReading(provider: .codex,
                                 state: state(.codex, windows: [window(0, reset: now.timeIntervalSince1970)]), now: now)
    check(expired.status == .refreshNeeded, "A reset at the current instant needs a new reading")
    let failed = MenuBarReading(provider: .codex,
                                state: state(.codex, windows: [window(0)], error: "network"), now: now)
    check(failed.status == .refreshNeeded, "A failed refresh marks even recent quota data as old")
    let loading = MenuBarReading(provider: .codex,
                                 state: state(.codex, windows: [window(0)], loading: true), now: now)
    check(loading.status == .available, "Loading preserves an existing fresh quota")
    var noReset = window(20)
    noReset.resetsAt = nil
    let withoutReset = MenuBarReading(provider: .gemini, state: state(.gemini, windows: [noReset]), now: now)
    check(withoutReset.status == .available && withoutReset.remaining == 80,
          "A missing reset timestamp does not discard a known quota percentage")
    let multi = MenuBarReading(provider: .codex,
                              state: state(.codex, windows: [window(10, minutes: 300), window(60)]), now: now)
    check(multi.window?.windowDurationMins == 10080 && multi.remaining == 40,
          "The miniature bar uses the representative weekly window rather than the first short window")
    let english = full.description(korean: false)
    let korean = full.description(korean: true)
    check(english.contains("Codex") && english.contains("Weekly") && english.contains("100%") &&
          english.contains("remaining") && english.lowercased().contains("reset"),
          "English accessibility text preserves service, period, quota, and reset information")
    check(korean.contains("Codex") && korean.contains("주간") && korean.contains("100%") &&
          korean.contains("남음") && korean.contains("초기화"),
          "Korean accessibility text preserves service, period, quota, and reset information")
    check(!failed.description(korean: false).contains("100% remaining") &&
          !expired.description(korean: true).contains("100% 남음"),
          "Stale and expired accessibility text does not announce cached quota as current")
    check(withoutReset.description(korean: false).lowercased().contains("reset") &&
          withoutReset.description(korean: true).contains("초기화"),
          "Accessibility text explicitly reports missing reset information")

    struct Raster {
        let rep: NSBitmapImageRep
        var pixels: Data { Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh) }
        func colorCount(column: Int, scale: Int) -> Int {
            var result = 0
            for x in (column * 8 * scale)..<((column + 1) * 8 * scale) {
                for y in 0..<rep.pixelsHigh {
                    guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let components = [color.redComponent, color.greenComponent, color.blueComponent]
                    if color.alphaComponent > 0.5 && components.max()! - components.min()! > 0.12 { result += 1 }
                }
            }
            return result
        }
    }
    func render(_ image: NSImage, scale: Int) throws -> Raster {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                        pixelsWide: Int(MenuBarIcon.size.width) * scale,
                                        pixelsHigh: Int(MenuBarIcon.size.height) * scale,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let bytes = rep.bitmapData, let context = NSGraphicsContext(bitmapImageRep: rep) else {
            throw NSError(domain: "MenuBarChecks", code: 1)
        }
        bytes.initialize(repeating: 0, count: rep.bytesPerRow * rep.pixelsHigh)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        image.draw(in: NSRect(origin: .zero, size: MenuBarIcon.size))
        context.flushGraphics()
        return Raster(rep: rep)
    }

    let asymmetric = [full, empty, half]
    let unknown = ProviderID.allCases.map { MenuBarReading(provider: $0, state: ProviderState(), now: now) }
    let zeros = ProviderID.allCases.map { reading($0, 100) }
    for dark in [false, true] {
        let icon = MenuBarIcon.image(readings: asymmetric, dark: dark)
        let unknownIcon = MenuBarIcon.image(readings: unknown, dark: dark)
        let zeroIcon = MenuBarIcon.image(readings: zeros, dark: dark)
        check([icon, unknownIcon, zeroIcon].allSatisfy { $0.size == NSSize(width: 24, height: 18) && !$0.isTemplate },
              "\(dark ? "Dark" : "Light") menu images keep a fixed 24 by 18 point size and provider colors")
        for scale in [1, 2] {
            let rendered = try render(icon, scale: scale)
            let reordered = try render(MenuBarIcon.image(readings: Array(asymmetric.reversed()), dark: dark), scale: scale)
            let missing = try render(unknownIcon, scale: scale)
            let exhausted = try render(zeroIcon, scale: scale)
            let fullCount = rendered.colorCount(column: 0, scale: scale)
            let zeroCount = rendered.colorCount(column: 1, scale: scale)
            let halfCount = rendered.colorCount(column: 2, scale: scale)
            let context = "\(dark ? "dark" : "light"), \(scale)x"
            check(fullCount > 0 && zeroCount == 0 && halfCount > 0 &&
                  Double(fullCount) > Double(halfCount) * 1.5 && Double(fullCount) < Double(halfCount) * 2.6,
                  "Rendered full, zero, and half quotas have proportionate colored fill (\(context))")
            check(rendered.pixels == reordered.pixels,
                  "Rendered service positions remain Codex, Claude, Gemini regardless of input order (\(context))")
            check(missing.pixels != exhausted.pixels &&
                  (0..<3).allSatisfy { missing.colorCount(column: $0, scale: scale) == 0 },
                  "Unknown dashed marks are neutral and visibly different from real zero quotas (\(context))")
        }
    }
}
