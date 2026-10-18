import AppKit
import SwiftUI
import UsageCore

@main struct PopupVerifier {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        var checks = 0
        func check(_ condition: Bool, _ message: String, geometry: String? = nil) {
            guard condition else {
                fputs("FAIL: \(message)\n", stderr)
                if let geometry { fputs("GEOMETRY: \(geometry)\n", stderr) }
                exit(1)
            }
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

        try runMenuBarChecks { condition, message in check(condition, message) }

        let store = UsageStore(demo: true)
        let now = Date()
        let window = ProviderWindow(id: "weekly", usedPercent: 40, windowDurationMins: 10080,
                                    resetsAt: now.addingTimeInterval(3 * 86400).timeIntervalSince1970)
        let freshWeb = ProviderSnapshot(provider: .claude, plan: nil, windows: [window], updatedAt: now, source: "Claude web")
        check(ProviderState(snapshot: freshWeb).hasFreshClaudeWeb(at: now), "Fresh Claude web values take priority over CLI reads")
        check(!ProviderState(snapshot: freshWeb).hasFreshClaudeWeb(at: now.addingTimeInterval(601)), "Stale web values allow the Claude CLI to refresh again")
        check(!ProviderState(snapshot: freshWeb, error: "network").hasFreshClaudeWeb(at: now), "A failed web refresh permits CLI recovery")
        check(ProviderState(snapshot: freshWeb).pace(for: window, at: now) != nil, "Fresh quota windows retain a pace marker")
        check(ProviderState(snapshot: freshWeb).pace(for: window, at: now.addingTimeInterval(601)) == nil,
              "Stale quota windows hide the pace marker")
        check(ProviderState(snapshot: freshWeb, error: "network").pace(for: window, at: now) == nil,
              "Failed quota reads hide the pace marker")
        check(!UsageStore.acceptsBridgePayload(Data("{}".utf8)), "Bridge schema validation rejects empty objects")
        check(!UsageStore.acceptsBridgePayload(Data(#"{"provider":"codex","error":"network"}"#.utf8)), "Bridge cannot overwrite Codex with an error")
        check(UsageStore.acceptsBridgePayload(Data(#"{"provider":"gemini","error":"auth_required"}"#.utf8)), "Known browser status errors remain supported")
        let controller = NSHostingController(rootView: UsagePopover(store: store, maximumHeight: 700))
        check(controller.sizeThatFits(in: NSSize(width: 460, height: 0)).height >= 300,
              "A zero-height host proposal cannot collapse the menu content")
        let host = NSHostingView(rootView: UsagePopover(store: store, maximumHeight: 700))
        check(host.fittingSize.width == 460 && host.fittingSize.height >= 300,
              "Menu content has a usable size before its first layout")
        let compact = settle(host)
        let panel = NSHostingView(rootView: UsagePanel(store: store))
        // Match the production viewport limit: CI displays can be shorter than
        // the requested 700pt popover even when its content measures correctly.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let screenCap = max(240, (screen?.visibleFrame.height ?? 800) - 24)
        let regularCap = min(700, screenCap)
        let contentHeight = panel.fittingSize.height
        let expectedCompact = min(regularCap, ceil(contentHeight))
        check(abs(compact.height - expectedCompact) <= 1,
              "Popover fits the measured weekly content within the current display",
              geometry: "actual=\(compact), expectedHeight=\(expectedCompact), contentHeight=\(contentHeight), maximumHeight=700, screenCap=\(screenCap), screens=\(NSScreen.screens.map(\.visibleFrame))")

        store.showSettings = true
        let expanded = settle(host)
        check(expanded.height >= compact.height && expanded.height <= regularCap,
              "Settings expand the popover without exceeding its height limit",
              geometry: "expanded=\(expanded), compact=\(compact), effectiveCap=\(regularCap)")
        store.showSettings = false
        let collapsed = settle(host)
        check(abs(collapsed.height - compact.height) <= 1,
              "Closing settings restores the compact height",
              geometry: "collapsed=\(collapsed), compact=\(compact), effectiveCap=\(regularCap)")

        store.showSettings = true
        let shortScreen = NSHostingView(rootView: UsagePopover(store: store, maximumHeight: 420))
        let shortSize = settle(shortScreen)
        let shortCap = min(420, screenCap)
        check(shortSize.height == shortCap,
              "Two windows with settings stay within a short screen viewport",
              geometry: "actual=\(shortSize), expectedHeight=\(shortCap), maximumHeight=420, screenCap=\(screenCap)")
        let overflowing = settle(NSHostingView(rootView: UsagePanel(store: store)))
        check(overflowing.height > shortCap,
              "Overflowing content keeps its full height for scrolling",
              geometry: "fullContent=\(overflowing), clippedViewport=\(shortSize)")

        store.providers = [:]
        store.showSettings = false
        store.providers[.codex] = ProviderState(error: "A connection error with enough text to wrap onto more than one line.")
        let disconnected = settle(host)
        check(disconnected.height > 200 && disconnected.height <= regularCap,
              "The disconnected state remains visible",
              geometry: "disconnected=\(disconnected), effectiveCap=\(regularCap)")
        store.providers[.codex] = ProviderState(loading: true)
        check(settle(host).height > 200, "The loading state remains visible")
        print("\(checks) popup layout checks passed")
    }
}
