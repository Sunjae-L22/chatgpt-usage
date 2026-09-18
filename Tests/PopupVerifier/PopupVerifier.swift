import AppKit
import SwiftUI
import UsageCore

@main struct PopupVerifier {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
            checks += 1
            print("PASS: \(message)")
        }
        func settle<V: View>(_ host: NSHostingView<V>) -> NSSize {
            for _ in 0..<12 {
                host.frame.size = host.fittingSize
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            return host.fittingSize
        }

        let store = UsageStore(demo: true)
        let controller = NSHostingController(rootView: UsagePopover(store: store, maximumHeight: 700))
        check(controller.sizeThatFits(in: NSSize(width: 370, height: 0)).height >= 300,
              "A zero-height host proposal cannot collapse the menu content")
        let host = NSHostingView(rootView: UsagePopover(store: store, maximumHeight: 700))
        check(host.fittingSize.width == 370 && host.fittingSize.height >= 300,
              "Menu content has a usable size before its first layout")
        let compact = settle(host)
        let panel = NSHostingView(rootView: UsagePanel(store: store))
        check(abs(compact.height - min(700, panel.fittingSize.height)) <= 1,
              "Popover fits the measured weekly content")

        store.showSettings = true
        let expanded = settle(host)
        check(expanded.height > compact.height && expanded.height <= 700,
              "Settings expand the popover without exceeding its height limit")
        store.showSettings = false
        check(abs(settle(host).height - compact.height) <= 1,
              "Closing settings restores the compact height")

        let reset = Date().addingTimeInterval(3 * 86400).timeIntervalSince1970
        store.response = try LimitsResponse.decode(Data("""
        {"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":\(reset)},"secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":\(reset)}}}
        """.utf8))
        store.showSettings = true
        let shortScreen = NSHostingView(rootView: UsagePopover(store: store, maximumHeight: 420))
        check(settle(shortScreen).height == 420,
              "Two windows with settings stay within a short screen viewport")
        check(settle(NSHostingView(rootView: UsagePanel(store: store))).height > 420,
              "Overflowing content keeps its full height for scrolling")

        store.response = nil
        store.showSettings = false
        store.error = "A connection error with enough text to wrap onto more than one line."
        let disconnected = settle(host)
        check(disconnected.height > 200 && disconnected.height <= 700,
              "The disconnected state remains visible")
        store.error = nil
        store.isLoading = true
        check(settle(host).height > 200, "The loading state remains visible")
        print("\(checks) popup layout checks passed")
    }
}
