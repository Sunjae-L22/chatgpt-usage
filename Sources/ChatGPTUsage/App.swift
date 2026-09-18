import SwiftUI
import AppKit
import ServiceManagement
import UsageCore

@MainActor private enum AppWindows {
    static var dashboard: NSWindow?
    static func show(_ store: UsageStore) {
        if let dashboard { dashboard.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 370, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "ChatGPT Usage"
        window.contentView = NSHostingView(rootView: ScrollView { UsagePanel(store: store) }.frame(minWidth: 370, maxWidth: 370))
        window.isReleasedWhenClosed = false
        window.center(); window.makeKeyAndOrderFront(nil)
        dashboard = window
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor final class UsageStore: ObservableObject {
    @Published var response: LimitsResponse?
    @Published var updatedAt: Date?
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedBucket = "codex"
    @Published var showSettings = false
    @Published var language = UserDefaults.standard.string(forKey: "language") ?? (Locale.preferredLanguages.first?.hasPrefix("ko") == true ? "ko" : "en") {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    @Published var binaryOverride = UserDefaults.standard.string(forKey: "codexBinary") ?? ""
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var settingsMessage: String?
    @Published var now = Date()
    let demo: Bool
    private var timer: Timer?
    private var clockTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(demo: Bool = false) {
        self.demo = demo
        if demo {
            let reset = Date().addingTimeInterval(3.5 * 86400).timeIntervalSince1970
            let json = """
            {"rateLimitsByLimitId":{"codex":{"limitId":"codex","planType":"pro","primary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":\(reset)},"secondary":null},"spark":{"limitName":"Example extra limit","primary":{"usedPercent":18,"windowDurationMins":300,"resetsAt":\(Date().addingTimeInterval(10800).timeIntervalSince1970)}}}}
            """
            response = try? LimitsResponse.decode(Data(json.utf8)); updatedAt = Date()
        }
    }
    func start() {
        guard !demo, timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func t(_ en: String, _ ko: String) -> String { language == "ko" ? ko : en }
    var bucket: LimitBucket? { response?.buckets.first { $0.id == selectedBucket }?.bucket ?? response?.buckets.first?.bucket }
    func stale(at now: Date) -> Bool { error != nil || updatedAt.map { now.timeIntervalSince($0) > 600 } ?? true }
    func label(at now: Date) -> String {
        guard let window = bucket?.headline, let remaining = window.remaining else { return "C —" }
        let expired = window.resetDate.map { $0 <= now } ?? false
        return "C \(Int(remaining.rounded(.down)))%\(stale(at: now) || expired ? " ?" : "")"
    }
    func refresh() {
        guard !demo, !isLoading else { return }
        guard let binary = CodexClient.discover(override: binaryOverride) else {
            error = localError(.missingBinary); return
        }
        isLoading = true
        Task {
            let result = await Task.detached { () -> Result<LimitsResponse, Error> in
                Result { try CodexClient().fetch(binary: binary) }
            }.value
            isLoading = false
            switch result {
            case .success(let data):
                response = data; updatedAt = Date(); error = nil
                if !data.buckets.contains(where: { $0.id == selectedBucket }) { selectedBucket = data.buckets.first?.id ?? "codex" }
            case .failure(let failure): error = localError(failure as? UsageError ?? .protocolError)
            }
        }
    }
    func localError(_ failure: UsageError) -> String {
        guard language == "ko" else { return failure.localizedDescription }
        switch failure {
        case .missingBinary: return "Mac용 ChatGPT 또는 Codex를 설치하고 ChatGPT 계정으로 로그인하세요."
        case .launch: return "Codex를 실행할 수 없습니다. 설정에서 실행 파일을 선택하세요."
        case .timeout: return "20초 안에 응답이 없었습니다. 연결 상태를 확인하고 다시 시도하세요."
        case .disconnected: return "Codex 연결이 종료되었습니다. Codex 업데이트 후 다시 시도하세요."
        case .noLimits: return "이 계정에서 한도 정보가 반환되지 않았습니다. API 키 로그인은 구독 한도를 제공하지 않을 수 있습니다."
        case .unavailable: return "사용량을 조회할 수 없습니다. Codex의 ChatGPT 로그인 상태를 확인하세요."
        case .protocolError: return "Codex 응답을 읽지 못했습니다. 앱과 Codex를 업데이트하세요."
        }
    }
    func chooseBinary() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = t("Select the codex executable", "codex 실행 파일 선택")
        if panel.runModal() == .OK, let url = panel.url {
            binaryOverride = url.path; UserDefaults.standard.set(url.path, forKey: "codexBinary"); refresh()
        }
    }
    func resetBinary() { binaryOverride = ""; UserDefaults.standard.removeObject(forKey: "codexBinary"); refresh() }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            settingsMessage = SMAppService.mainApp.status == .requiresApproval ? t("Allow ChatGPT Usage in System Settings → Login Items.", "시스템 설정 → 로그인 항목에서 ChatGPT Usage를 허용하세요.") : nil
        } catch { settingsMessage = t("Could not change login settings. Keep the app in a permanent folder and retry.", "로그인 설정을 변경하지 못했습니다. 앱을 고정된 폴더로 옮긴 뒤 다시 시도하세요.") }
    }
}

struct UsagePanel: View {
    @ObservedObject var store: UsageStore
    private let accent = Color(red: 0.23, green: 0.75, blue: 0.62)
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 24)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ChatGPT Usage").font(.system(size: 19, weight: .semibold))
                        Text(store.t("Codex account limits", "Codex 계정 사용 한도")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.showSettings.toggle() } label: { Image(systemName: "gearshape") }.buttonStyle(.borderless)
                        .help(store.t("Settings", "설정"))
                }
                if store.demo { Text(store.t("DEMO · Sample data", "데모 · 예시 데이터")).font(.caption.weight(.semibold)).foregroundStyle(.orange) }
                if let buckets = store.response?.buckets, buckets.count > 1 {
                    Picker(store.t("Limit", "한도"), selection: $store.selectedBucket) {
                        ForEach(buckets, id: \.id) { entry in
                            Text(entry.bucket.limitName ?? (entry.id == "codex" ? "Codex" : entry.id)).tag(entry.id)
                        }
                    }.labelsHidden().pickerStyle(.menu)
                }
                if let bucket = store.bucket {
                    HStack {
                        Text(store.t("PLAN", "요금제")).font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.secondary)
                        Text(bucket.planType ?? store.t("Not reported", "정보 없음")).font(.caption.weight(.medium))
                        Spacer()
                        Text(store.t("REMAINING", "남은 한도")).font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(accent)
                    }
                    ForEach(Array(bucket.windows.enumerated()), id: \.offset) { _, window in
                        windowCard(window, now: context.date)
                    }
                    if bucket.windows.isEmpty { Text(store.t("No quota window was returned for this limit.", "이 항목에서 한도 기간이 반환되지 않았습니다.")).foregroundStyle(.secondary) }
                } else if store.isLoading {
                    HStack { ProgressView().controlSize(.small); Text(store.t("Reading your account limits…", "계정 한도를 확인하고 있습니다…")) }.padding(.vertical, 30)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.t("Connect through Codex", "Codex로 연결하기")).font(.headline)
                        Text(store.t("Sign in to Codex with ChatGPT, then refresh. Your existing Codex installation handles authentication.", "Codex에 ChatGPT 계정으로 로그인한 뒤 새로고침하세요. 인증은 설치된 Codex가 처리합니다.")).font(.callout).foregroundStyle(.secondary)
                        Button(store.t("Open setup guide", "연결 방법 보기")) { openURL("https://github.com/Sunjae-L22/chatgpt-usage#setup") }
                    }.padding(.vertical, 12)
                }
                if let error = store.error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if store.showSettings { settings }
                Divider()
                HStack {
                    Circle().fill(store.stale(at: context.date) ? Color.orange : accent).frame(width: 5, height: 5)
                    VStack(alignment: .leading, spacing: 2) {
                        if let date = store.updatedAt {
                            Text(store.stale(at: context.date) ? store.t("Last known · refresh needed", "이전 값 · 새로고침 필요") : store.t("Updated", "업데이트"))
                            Text(date, style: .time).monospacedDigit()
                        } else { Text(store.t("Not connected", "연결 전")) }
                    }.font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }.disabled(store.isLoading || store.demo).help(store.t("Refresh", "새로고침"))
                    Button(store.t("Quit", "종료")) { NSApp.terminate(nil) }.buttonStyle(.borderless).font(.caption)
                }
                Text(store.t("Unofficial · Codex limits only · Refreshes every 5 min", "비공식 앱 · Codex 한도 표시 · 5분마다 조회")).font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(22).frame(width: 370)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .onAppear {
            if !store.demo && (store.updatedAt == nil || Date().timeIntervalSince(store.updatedAt!) > 60) { store.refresh() }
        }
    }
    private func durationName(_ window: LimitWindow) -> String {
        guard let minutes = window.windowDurationMins, minutes > 0 else { return store.t("Reported window", "기간 정보 없음") }
        if minutes == 10080 { return store.t("Weekly", "주간") }
        if minutes % 1440 == 0 { return store.t("\(minutes / 1440)-day", "\(minutes / 1440)일") }
        if minutes % 60 == 0 { return store.t("\(minutes / 60)-hour", "\(minutes / 60)시간") }
        return store.t("\(minutes)-minute", "\(minutes)분")
    }
    @ViewBuilder private func windowCard(_ window: LimitWindow, now: Date) -> some View {
        let expired = window.resetDate.map { $0 <= now } ?? false
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(durationName(window)).font(.headline)
                Spacer()
                Text(window.remaining.map { "\(Int($0.rounded(.down)))" } ?? "—").font(.system(size: 42, weight: .semibold, design: .rounded)).monospacedDigit()
                if window.remaining != nil { Text("%").font(.title3).foregroundStyle(.secondary) }
            }
            if let remaining = window.remaining {
                QuotaPaceBar(remaining: remaining,
                             pace: store.stale(at: now) ? nil : window.pace(at: now),
                             weekly: window.windowDurationMins == 10080,
                             korean: store.language == "ko")
            }
            if let resetDate = window.resetDate {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "clock").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(expired ? store.t("Reset time passed · refresh needed", "초기화 시각 경과 · 새로고침 필요") : countdown(resetDate, now: now)).font(.callout.weight(.medium))
                        Text(resetDate.formatted(date: .abbreviated, time: .shortened) + " · " + (TimeZone.current.abbreviation() ?? TimeZone.current.identifier)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else { Text(store.t("Reset time not reported", "초기화 시각 정보 없음")).font(.caption).foregroundStyle(.secondary) }
            if !store.stale(at: now), let pace = window.pace(at: now), (window.windowDurationMins ?? 0) >= 1440 {
                Divider()
                HStack(alignment: .top) {
                    Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("\(pace.percentagePointsPerDay.formatted(.number.precision(.fractionLength(1))))% of quota per day", "하루 \(pace.percentagePointsPerDay.formatted(.number.precision(.fractionLength(1))))%p 균등 배분")).font(.callout.weight(.medium))
                        Text(store.t("If you spread the remainder evenly until reset. A pacing guide, not a daily limit.", "초기화까지 남은 한도를 균등하게 나눈 참고값입니다. 실제 일일 한도는 아닙니다.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }.padding(16).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            .opacity(store.stale(at: now) || expired ? 0.65 : 1)
    }
    private func countdown(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86400, hours = seconds % 86400 / 3600, minutes = seconds % 3600 / 60
        let time = days > 0 ? store.t("\(days)d \(hours)h", "\(days)일 \(hours)시간") : hours > 0 ? store.t("\(hours)h \(minutes)m", "\(hours)시간 \(minutes)분") : store.t("\(max(1, minutes))m", "\(max(1, minutes))분")
        return store.t("Resets in \(time)", "\(time) 후 초기화")
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(store.t("Language", "언어"), selection: $store.language) { Text("English").tag("en"); Text("한국어").tag("ko") }
            Toggle(store.t("Launch at login", "로그인 시 실행"), isOn: Binding(get: { store.loginEnabled }, set: { store.setLogin($0) }))
            HStack {
                Button(store.t("Choose Codex…", "Codex 선택…")) { store.chooseBinary() }
                Button(store.t("Auto-detect", "자동 찾기")) { store.resetBinary() }
            }
            Text(store.binaryOverride.isEmpty ? store.t("Codex location: automatic", "Codex 위치: 자동 검색") : URL(fileURLWithPath: store.binaryOverride).lastPathComponent).font(.caption).foregroundStyle(.secondary)
            if let message = store.settingsMessage { Text(message).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button(store.t("Open window", "창으로 보기")) { AppWindows.show(store) }
                Button("GitHub") { openURL("https://github.com/Sunjae-L22/chatgpt-usage") }
                Button(store.t("Usage dashboard", "사용량 페이지")) { openURL("https://chatgpt.com/codex/settings/usage") }
            }
            Text(store.t("v0.2.0 · No app telemetry. Codex handles sign-in and the network request. Plan names are displayed as reported.", "v0.2.0 · 앱 자체 분석 수집 없음. 인증과 조회 요청은 Codex가 처리합니다. 요금제명은 서버 값 그대로 표시합니다.")).font(.caption2).foregroundStyle(.secondary)
        }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
    private func openURL(_ value: String) { if let url = URL(string: value) { NSWorkspace.shared.open(url) } }
}

#if !LAYOUT_TEST
@main struct ChatGPTUsageApp: App {
    @StateObject private var store: UsageStore
    init() {
        let args = CommandLine.arguments
        if args.contains("--check") {
            do {
                guard let binary = CodexClient.discover() else { throw UsageError.missingBinary }
                let response = try CodexClient().fetch(binary: binary)
                // Only quota data: never include the account identity or raw server responses.
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
            let hosting = NSHostingView(rootView: UsagePanel(store: instance).environment(\.colorScheme, .dark))
            let size = hosting.fittingSize
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.layoutSubtreeIfNeeded()
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    do { try data.write(to: URL(fileURLWithPath: args[index + 1])); exit(0) }
                    catch { exit(1) }
                }
            }
            exit(1)
        }
        instance.start()
        if args.contains("--window") {
            DispatchQueue.main.async { AppWindows.show(instance) }
        }
    }
    var body: some Scene {
        MenuBarExtra {
            UsagePopover(store: store)
        } label: {
            Text(store.label(at: store.now))
        }.menuBarExtraStyle(.window)
    }
}
#endif
