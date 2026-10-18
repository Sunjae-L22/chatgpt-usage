import AppKit
import SwiftUI
import UsageCore

struct MenuBarReading {
    enum Status: Equatable {
        case available, refreshNeeded, unavailable
    }

    let provider: ProviderID
    let window: ProviderWindow?
    let remaining: Double?
    let status: Status

    init(provider: ProviderID, state: ProviderState, now: Date) {
        self.provider = provider
        window = state.snapshot?.headline
        remaining = window?.limit.remaining
        if remaining == nil {
            status = .unavailable
        } else if state.stale(at: now) || window?.limit.resetDate.map({ $0 <= now }) == true {
            status = .refreshNeeded
        } else {
            status = .available
        }
    }

    func description(korean: Bool) -> String {
        let period: String
        switch window?.windowDurationMins {
        case 10080: period = korean ? "주간" : "Weekly"
        case 300: period = korean ? "5시간" : "5-hour"
        case .some(let minutes): period = korean ? "\(minutes)분" : "\(minutes) min"
        case nil: period = korean ? "사용 한도" : "Quota"
        }
        let name = window?.label.map { "\(period) · \($0)" } ?? period
        let value: String
        switch status {
        case .available:
            let percent = (remaining ?? 0).formatted(.number.precision(.fractionLength(provider == .codex ? 0...0 : 0...1)))
            value = korean ? "\(percent)% 남음" : "\(percent)% remaining"
        case .refreshNeeded: value = korean ? "새로고침 필요" : "Refresh needed"
        case .unavailable: value = korean ? "사용량 확인 필요" : "Usage unavailable"
        }
        let reset: String
        if let date = window?.limit.resetDate {
            let formatted = date.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: korean ? "ko_KR" : "en_US")))
            reset = korean ? "초기화 \(formatted)" : "Resets \(formatted)"
        } else {
            reset = korean ? "초기화 시각 미제공" : "Reset not reported"
        }
        return "\(provider.title) · \(name): \(value) · \(reset)"
    }
}

enum MenuBarIcon {
    // AppKit adds the standard status-item padding around this fixed-size image.
    static let size = NSSize(width: 24, height: 18)

    static func image(readings: [MenuBarReading], dark: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            let track = (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? 0.25 : 0.20)
            let unavailable = (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.60)
            for (index, provider) in ProviderID.allCases.enumerated() {
                let rect = NSRect(x: CGFloat(1 + index * 8), y: 2, width: 5, height: 14)
                guard let reading = readings.first(where: { $0.provider == provider }),
                      reading.status == .available, let remaining = reading.remaining else {
                    // Broken marks are unknown/stale; an empty solid track means a real 0%.
                    unavailable.setFill()
                    for y in stride(from: 2, through: 14, by: 4) {
                        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: CGFloat(y), width: 5, height: 2), xRadius: 0.6, yRadius: 0.6).fill()
                    }
                    continue
                }
                let outline = NSBezierPath(roundedRect: rect, xRadius: 1.2, yRadius: 1.2)
                track.setFill(); outline.fill()
                NSGraphicsContext.saveGraphicsState()
                outline.addClip()
                color(for: provider, dark: dark).setFill()
                NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * remaining / 100).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func color(for provider: ProviderID, dark: Bool) -> NSColor {
        switch provider {
        case .codex: return dark ? NSColor(srgbRed: 0.38, green: 0.76, blue: 0.67, alpha: 1) : NSColor(srgbRed: 0.09, green: 0.46, blue: 0.40, alpha: 1)
        case .claude: return dark ? NSColor(srgbRed: 0.89, green: 0.61, blue: 0.47, alpha: 1) : NSColor(srgbRed: 0.66, green: 0.33, blue: 0.21, alpha: 1)
        case .gemini: return dark ? NSColor(srgbRed: 0.53, green: 0.69, blue: 0.98, alpha: 1) : NSColor(srgbRed: 0.16, green: 0.36, blue: 0.71, alpha: 1)
        }
    }
}

struct MenuBarIndicator: View {
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let readings = ProviderID.allCases.map { MenuBarReading(provider: $0, state: store.state($0), now: store.now) }
        let summary = (["AI Usage", store.t("Left to right: Codex · Claude · Gemini", "왼쪽부터 Codex · Claude · Gemini")]
            + readings.map { $0.description(korean: store.language == "ko") }).joined(separator: "\n")
        Image(nsImage: MenuBarIcon.image(readings: readings, dark: colorScheme == .dark))
            .renderingMode(.original)
            .accessibilityLabel("AI Usage")
            .accessibilityValue(summary)
            .help(summary)
    }
}
