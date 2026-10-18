import SwiftUI
import AppKit
import ServiceManagement
import UsageCore

@MainActor private enum AppWindows {
    static var dashboard: NSWindow?
    static func show(_ store: UsageStore) {
        if let dashboard { dashboard.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 700), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "AI Usage"
        window.contentView = NSHostingView(rootView: UsagePopover(store: store, maximumHeight: 760))
        window.isReleasedWhenClosed = false; window.center(); window.makeKeyAndOrderFront(nil)
        dashboard = window; NSApp.activate(ignoringOtherApps: true)
    }
}

struct ProviderState {
    var snapshot: ProviderSnapshot?
    var error: String?
    var loading = false
    func stale(at now: Date) -> Bool { error != nil || snapshot.map { now.timeIntervalSince($0.updatedAt) > 600 } ?? true }
    func hasFreshClaudeWeb(at now: Date) -> Bool { snapshot?.source == "Claude web" && !stale(at: now) }
    func pace(for window: ProviderWindow, at now: Date) -> Pace? { stale(at: now) ? nil : window.limit.pace(at: now) }
}

@MainActor final class UsageStore: ObservableObject {
    @Published var providers: [ProviderID: ProviderState] = [:]
    @Published var showSettings = false
    @Published var language = UserDefaults.standard.string(forKey: "language") ?? (Locale.preferredLanguages.first?.hasPrefix("ko") == true ? "ko" : "en") {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    @Published var binaryOverride = UserDefaults.standard.string(forKey: "codexBinary") ?? ""
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var settingsMessage: String?
    @Published var now = Date()
    let bridge = UsageBridge()
    let demo: Bool
    private var timer: Timer?
    private var clockTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    init(demo: Bool = false) {
        self.demo = demo
        if demo {
            for (id, plan, values) in [(ProviderID.codex, "Pro", [42.0, 33.0]), (.claude, "Pro", [64.0, 28.0]), (.gemini, "Google AI Pro", [17.5, 46.2])] {
                let windows = zip([300, 10080], values).map { minutes, used in
                    ProviderWindow(id: "\(minutes)", usedPercent: used, windowDurationMins: minutes, resetsAt: Date().addingTimeInterval(Double(minutes) * 60 * (minutes == 300 ? 0.4 : 0.55)).timeIntervalSince1970)
                }
                providers[id] = ProviderState(snapshot: ProviderSnapshot(provider: id, plan: plan, windows: windows, source: "Demo"))
            }
        }
    }
    func t(_ en: String, _ ko: String) -> String { language == "ko" ? ko : en }
    func state(_ id: ProviderID) -> ProviderState { providers[id] ?? ProviderState() }
    var isLoading: Bool { providers.values.contains { $0.loading } }
    func start() {
        guard !demo, timer == nil else { return }
        bridge.start(validate: Self.acceptsBridgePayload) { [weak self] data in self?.receive(data) }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.now = Date() } }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func receive(_ data: Data) {
        if let snapshot = try? ProviderSnapshot.decodeBridge(data) {
            // Ignore late or replayed measurements rather than making old data appear fresh.
            if let previous = state(snapshot.provider).snapshot, previous.updatedAt > snapshot.updatedAt { return }
            providers[snapshot.provider] = ProviderState(snapshot: snapshot, loading: state(snapshot.provider).loading)
        } else if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = object["provider"] as? String, let provider = ProviderID(rawValue: raw), provider != .codex,
                  let code = object["error"] as? String {
            let message: String
            switch code {
            case "auth_required": message = t("Sign in on the usage page, then refresh the extension.", "사용량 페이지에 로그인한 뒤 확장에서 새로고침하세요.")
            case "rate_limited": message = t("Too many requests. Retry in a few minutes.", "조회가 잠시 제한되었습니다. 잠시 후 다시 시도하세요.")
            case "select_account": message = t("Multiple Claude organizations prevent automatic connection.", "여러 Claude 조직이 있어 자동 연결할 수 없습니다.")
            case "schema_changed": message = t("The service response changed. An app update may be needed.", "서비스 응답 형식이 바뀌었습니다. 앱 업데이트가 필요할 수 있습니다.")
            default: message = t("Could not refresh. Check the usage page and extension.", "새로고침하지 못했습니다. 사용량 페이지와 확장을 확인하세요.")
            }
            var state = state(provider); state.error = message; providers[provider] = state
        }
    }
    static func acceptsBridgePayload(_ data: Data) -> Bool {
        if (try? ProviderSnapshot.decodeBridge(data)) != nil { return true }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["provider"] as? String, let provider = ProviderID(rawValue: raw), provider != .codex,
              let code = object["error"] as? String else { return false }
        return ["auth_required", "rate_limited", "select_account", "schema_changed", "network"].contains(code)
    }
    func refresh() {
        guard !demo else { return }
        if !state(.codex).loading {
            if let binary = CodexClient.discover(override: binaryOverride) {
                var state = state(.codex); state.loading = true; providers[.codex] = state
                Task {
                    let result = await Task.detached { Result { try CodexClient().fetch(binary: binary) } }.value
                    var state = self.state(.codex); state.loading = false
                    switch result {
                    case .success(let response): state.snapshot = .codex(response); state.error = nil
                    case .failure: state.error = t("Check your Codex sign-in, then refresh.", "Codex 로그인 상태를 확인하고 새로고침하세요.")
                    }
                    providers[.codex] = state
                }
            } else { var state = state(.codex); state.error = t("Install Codex and sign in with ChatGPT.", "Codex를 설치하고 ChatGPT 계정으로 로그인하세요."); providers[.codex] = state }
        }
        // A fresh browser measurement wins over the experimental CLI route.
        if !state(.claude).loading, !state(.claude).hasFreshClaudeWeb(at: Date()), let binary = ClaudeClient.discover() {
            var state = state(.claude); state.loading = true; providers[.claude] = state
            Task {
                let result = await Task.detached { Result { try ClaudeClient().fetch(binary: binary) } }.value
                var state = self.state(.claude); state.loading = false
                if !state.hasFreshClaudeWeb(at: Date()) {
                    switch result {
                    case .success(let snapshot): state.snapshot = snapshot; state.error = nil
                    case .failure: state.error = t("Connect the browser extension to read your Claude plan limits.", "브라우저 확장을 연결하면 Claude 요금제 한도를 확인할 수 있어요.")
                    }
                }
                providers[.claude] = state
            }
        }
    }
    func chooseBinary() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = t("Select the codex executable", "codex 실행 파일 선택")
        if panel.runModal() == .OK, let url = panel.url { binaryOverride = url.path; UserDefaults.standard.set(url.path, forKey: "codexBinary"); refresh() }
    }
    func resetBinary() { binaryOverride = ""; UserDefaults.standard.removeObject(forKey: "codexBinary"); refresh() }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            settingsMessage = SMAppService.mainApp.status == .requiresApproval ? t("Allow AI Usage in System Settings → Login Items.", "시스템 설정 → 로그인 항목에서 AI Usage를 허용하세요.") : nil
        } catch { settingsMessage = t("Keep the app in a permanent folder and retry.", "앱을 고정된 폴더로 옮긴 뒤 다시 시도하세요.") }
    }
}

extension ProviderID {
    var accent: Color {
        switch self {
        case .codex: UsagePalette.adaptive(light: 0x187B69, dark: 0x55BFA8)
        case .claude: UsagePalette.adaptive(light: 0xA65734, dark: 0xD9936E)
        case .gemini: UsagePalette.adaptive(light: 0x356CC8, dark: 0x78A1EF)
        }
    }
    var symbol: String { switch self { case .codex: "terminal"; case .claude: "asterisk"; case .gemini: "sparkle" } }
    var usageURL: String { switch self { case .codex: "https://chatgpt.com/codex/settings/usage"; case .claude: "https://claude.ai/settings/usage"; case .gemini: "https://gemini.google.com/usage" } }
}

private enum UsagePalette {
    static let cardBase = adaptive(light: 0xFFFFFF, dark: 0x26272A)
    static let secondary = adaptive(light: 0x60636B, dark: 0xB0B4BD)
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

struct UsagePanel: View {
    @ObservedObject var store: UsageStore
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Text("AI Usage").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    if store.demo { Text("DEMO").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange).padding(6).background(.orange.opacity(0.1), in: Capsule()) }
                    Button { store.showSettings.toggle() } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 16)) }.buttonStyle(.plain).help(store.t("Connections & settings", "연결 및 설정"))
                }
                HStack {
                    Text(store.t("Quota remaining", "남은 사용 한도")).font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(store.t("Updates every 5 min", "5분마다 업데이트")).font(.system(size: 11))
                }.foregroundStyle(UsagePalette.secondary)
                VStack(spacing: 10) {
                    ForEach(ProviderID.allCases) { provider in ProviderCard(store: store, provider: provider, now: context.date) }
                }
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        Capsule().fill(UsagePalette.secondary).frame(width: 14, height: 5).accessibilityHidden(true)
                        Text(store.t("Quota left", "남은 한도"))
                    }
                    HStack(spacing: 5) {
                        Capsule().fill(UsagePalette.secondary).frame(width: 2, height: 11).accessibilityHidden(true)
                        Text(store.t("Time-left marker", "남은 시간 기준선"))
                    }
                }.font(.system(size: 11)).foregroundStyle(UsagePalette.secondary).frame(maxWidth: .infinity).padding(.top, 2)
                if store.showSettings { ConnectionSettings(store: store, bridge: store.bridge) }
                Divider()
                HStack(spacing: 8) {
                    Text(store.t("Unofficial · On your Mac", "비공식 앱 · 내 Mac에서")).font(.system(size: 11)).foregroundStyle(UsagePalette.secondary)
                    Spacer()
                    Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).disabled(store.isLoading || store.demo).help(store.t("Refresh local apps; use the extension to refresh browser quotas", "앱 한도 새로고침 · 웹 한도는 확장에서 새로고침"))
                    Button(store.t("Quit", "종료")) { NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(UsagePalette.secondary)
                }
            }.padding(20).frame(width: 460).background(Color(nsColor: .windowBackgroundColor))
        }.environment(\.locale, Locale(identifier: store.language))
    }
}

private struct ProviderCard: View {
    @ObservedObject var store: UsageStore
    let provider: ProviderID
    let now: Date
    @State private var expanded = false
    private var state: ProviderState { store.state(provider) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: provider.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(provider.accent).frame(width: 20, height: 20)
                Text(provider.title).font(.system(size: 16, weight: .semibold))
                if let plan = state.snapshot?.plan { Text(plan).font(.system(size: 11)).foregroundStyle(UsagePalette.secondary).lineLimit(1) }
                Spacer(minLength: 4)
                if state.loading { ProgressView().controlSize(.mini) }
                if let snapshot = state.snapshot {
                    if state.stale(at: now) { Image(systemName: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(.orange) }
                    else { Circle().fill(provider.accent).frame(width: 4, height: 4) }
                    Text(snapshot.updatedAt, style: .time).font(.system(size: 11)).foregroundStyle(UsagePalette.secondary)
                } else { Text(store.t("Not connected", "연결 전")).font(.system(size: 10)).foregroundStyle(UsagePalette.secondary) }
            }
            if let snapshot = state.snapshot, !snapshot.windows.isEmpty {
                ForEach(Array((expanded ? snapshot.windows : Array(snapshot.windows.prefix(2))))) { window in
                    windowRow(window)
                }
                if snapshot.windows.count > 2 {
                    Button(store.t(expanded ? "Show less" : "\(snapshot.windows.count - 2) more limits", expanded ? "접기" : "한도 \(snapshot.windows.count - 2)개 더 보기")) { expanded.toggle() }.buttonStyle(.plain).font(.caption).foregroundStyle(UsagePalette.secondary)
                }
                if state.stale(at: now) { Label(store.t("Last known values · refresh needed", "이전 값 · 새로고침 필요"), systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange) }
            } else {
                Text(store.t(provider == .codex ? "Your ChatGPT plan, through Codex." : "Connect once to see your plan limits here.", provider == .codex ? "Codex를 통해 ChatGPT 요금제 한도를 확인해요." : "한 번 연결하면 요금제 한도를 여기서 확인할 수 있어요.")).font(.system(size: 12)).foregroundStyle(UsagePalette.secondary)
                HStack {
                    Button(store.t("Connect", "연결하기")) { store.showSettings = true }.controlSize(.small)
                    Button(store.t("Open usage page ↗", "사용량 페이지 ↗")) { openURL(provider.usageURL) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(provider.accent)
                }
            }
            if let error = state.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }.padding(.horizontal, 14).padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14).fill(UsagePalette.cardBase)
                    .overlay { RoundedRectangle(cornerRadius: 14).fill(provider.accent.opacity(0.12)) }
            }
    }
    private func name(_ window: ProviderWindow) -> String {
        let duration: String
        switch window.windowDurationMins {
        case 10080: duration = store.t("Weekly", "주간")
        case 300: duration = store.t("5-hour", "5시간")
        case .some(let minutes): duration = store.t("\(minutes) min", "\(minutes)분")
        case nil: duration = store.t("Quota", "사용 한도")
        }
        return window.label.map { "\(duration) · \($0)" } ?? duration
    }
    private func percentage(_ remaining: Double) -> String {
        // Codex supplies integer usage. Other providers may supply genuine fractions.
        remaining.formatted(.number.precision(.fractionLength(provider == .codex ? 0...0 : 0...1)))
    }
    @ViewBuilder private func windowRow(_ window: ProviderWindow) -> some View {
        let limit = window.limit
        let expired = limit.resetDate.map { $0 <= now } ?? false
        let old = state.stale(at: now) || expired
        let pace = state.pace(for: window, at: now)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(name(window)).font(.system(size: 11, weight: .medium)).foregroundStyle(UsagePalette.secondary).lineLimit(1)
                Spacer()
                if let remaining = limit.remaining {
                    (Text(percentage(remaining)).font(.system(size: 22, weight: .semibold))
                     + Text("%").font(.system(size: 13, weight: .medium)).foregroundColor(UsagePalette.secondary))
                        .monospacedDigit().foregroundStyle(old ? UsagePalette.secondary : Color.primary)
                }
                else { Text("—").foregroundStyle(UsagePalette.secondary) }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 6)
                    if let remaining = limit.remaining { Capsule().fill(old ? Color.gray : provider.accent).frame(width: geometry.size.width * remaining / 100, height: 6) }
                    if let pace { Capsule().fill(Color.primary.opacity(0.9)).frame(width: 2, height: 12).overlay(Capsule().stroke(UsagePalette.cardBase, lineWidth: 0.5)).offset(x: max(0, min(geometry.size.width - 2, geometry.size.width * pace.remainingTimePercent / 100 - 1))) }
                }.frame(height: 12)
            }.frame(height: 12).accessibilityLabel(store.t("Remaining quota and time marker", "남은 한도와 시간 기준선"))
            HStack(spacing: 3) {
                if let reset = limit.resetDate {
                    if expired { Text(store.t("Reset passed · refresh", "초기화 시각 지남 · 새로고침")) }
                    else if store.language == "ko" { Text(reset, style: .relative); Text("후 초기화") }
                    else { Text("Resets in"); Text(reset, style: .relative) }
                } else { Text(store.t("Reset not reported", "초기화 시각 미제공")) }
                Spacer(minLength: 4)
                if let pace { Text(store.t("Time left \(Int(pace.remainingTimePercent.rounded()))%", "시간 \(Int(pace.remainingTimePercent.rounded()))% 남음")) }
            }.font(.system(size: 11)).foregroundStyle(UsagePalette.secondary).monospacedDigit()
        }.help(store.t("The vertical line marks time remaining. When the colored bar extends beyond it, quota is being used more slowly than an even pace. This is a reference, not a daily limit.", "세로선은 남은 시간 비율이에요. 색 막대가 선보다 길면 균등 페이스보다 여유 있게 쓰고 있어요. 실제 일일 한도가 아닌 참고 기준입니다."))
    }
}

private struct ConnectionSettings: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var bridge: UsageBridge
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.t("Connections", "서비스 연결")).font(.headline)
            Text(store.t("Codex reads your existing local login. Claude can use Claude Code. Browser quotas use the AI Usage extension.", "Codex는 기존 로그인을 사용해요. Claude Code 연결도 지원하며, 웹 사용량은 AI Usage 확장으로 연결해요.")).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(store.t("1. Load the included browser-extension folder in Chrome.\n2. Copy the pairing key below into the extension.\n3. Keep your signed-in usage pages open.", "1. Chrome에서 동봉된 browser-extension 폴더를 불러오세요.\n2. 아래 연결 키를 복사해 확장에 붙여 넣으세요.\n3. 로그인된 사용량 페이지를 열어 두세요.")).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(copied ? store.t("Copied", "복사됨") : store.t("Copy pairing key", "연결 키 복사")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(bridge.pairingToken, forType: .string); copied = true }.disabled(store.demo)
                Button(store.t("Reveal extension", "확장 폴더 보기")) {
                    if let url = Bundle.main.resourceURL?.appendingPathComponent("browser-extension") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
            Text(bridge.isRunning ? store.t("Local bridge ready · Usage only, no cookies copied", "로컬 연결 준비됨 · 사용량만 전달, 쿠키 복사 없음") : bridge.status).font(.system(size: 10)).foregroundStyle(bridge.isRunning ? Color.secondary : Color.orange)
            HStack { ForEach([ProviderID.claude, .gemini]) { provider in Button("\(provider.title) ↗") { openURL(provider.usageURL) } }; Button(store.t("New pairing key", "키 재발급")) { bridge.rotateToken(); copied = false } }
            Divider()
            Picker(store.t("Language", "언어"), selection: $store.language) { Text("English").tag("en"); Text("한국어").tag("ko") }
            Toggle(store.t("Launch at login", "로그인 시 실행"), isOn: Binding(get: { store.loginEnabled }, set: { store.setLogin($0) }))
            HStack { Button(store.t("Choose Codex…", "Codex 선택…")) { store.chooseBinary() }; Button(store.t("Auto-detect", "자동 찾기")) { store.resetBinary() }; Button(store.t("Open window", "창으로 보기")) { AppWindows.show(store) } }
            if let message = store.settingsMessage { Text(message).font(.caption).foregroundStyle(.orange) }
            Text("0.3.0 beta · No telemetry").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

private func openURL(_ value: String) { if let url = URL(string: value) { NSWorkspace.shared.open(url) } }

#if !LAYOUT_TEST
@main struct ChatGPTUsageApp: App {
    @StateObject private var store: UsageStore
    init() {
        let args = CommandLine.arguments
        if args.contains("--check") {
            do {
                guard let binary = CodexClient.discover() else { throw UsageError.missingBinary }
                let response = try CodexClient().fetch(binary: binary)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(response), as: UTF8.self)); exit(0)
            } catch { print(error.localizedDescription); exit(1) }
        }
        let demo = args.contains("--demo") || args.contains("--render-demo")
        let instance = UsageStore(demo: demo)
        if let index = args.firstIndex(of: "--language"), args.count > index + 1 { instance.language = args[index + 1] }
        _store = StateObject(wrappedValue: instance)
        if let index = args.firstIndex(of: "--render-demo"), args.count > index + 1 {
            NSApplication.shared.setActivationPolicy(.accessory)
            let scheme: ColorScheme = args.contains("--light") ? .light : .dark
            let hosting = NSHostingView(rootView: UsagePanel(store: instance).environment(\.colorScheme, scheme))
            hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize); hosting.layoutSubtreeIfNeeded()
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) { do { try data.write(to: URL(fileURLWithPath: args[index + 1])); exit(0) } catch { exit(1) } }
            }
            exit(1)
        }
        instance.start()
        if args.contains("--window") { DispatchQueue.main.async { AppWindows.show(instance) } }
    }
    var body: some Scene {
        MenuBarExtra { UsagePopover(store: store) } label: { MenuBarIndicator(store: store) }.menuBarExtraStyle(.window)
    }
}
#endif
