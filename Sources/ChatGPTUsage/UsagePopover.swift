import AppKit
import SwiftUI

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// MenuBarExtra asks for an ideal size. A ScrollView with only maxHeight can
/// answer zero, so give the host an explicit height before measuring content.
struct UsagePopover: View {
    @ObservedObject var store: UsageStore
    var maximumHeight: CGFloat = 760
    @State private var contentHeight: CGFloat = 560
    @State private var screenHeight: CGFloat = 760

    var body: some View {
        ScrollView {
            UsagePanel(store: store)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: PanelHeightKey.self, value: geometry.size.height)
                    }
                }
        }
        .frame(width: 370, height: min(contentHeight, maximumHeight, screenHeight))
        .onPreferenceChange(PanelHeightKey.self) { height in
            guard height.isFinite, height > 0 else { return }
            let measured = ceil(height)
            if abs(contentHeight - measured) >= 1 { contentHeight = measured }
        }
        .onAppear {
            // Leave room around the popover on the display containing the menu.
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            screenHeight = max(240, (screen?.visibleFrame.height ?? 800) - 24)
        }
    }
}
