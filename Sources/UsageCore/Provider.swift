import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case codex, claude, gemini
    public var id: String { rawValue }
    public var title: String { switch self { case .codex: return "Codex"; case .claude: return "Claude"; case .gemini: return "Gemini" } }
}

public struct ProviderWindow: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var label: String?
    public var usedPercent: Double?
    public var windowDurationMins: Int?
    public var resetsAt: Double?
    public init(id: String, label: String? = nil, usedPercent: Double?, windowDurationMins: Int?, resetsAt: Double?) {
        self.id = id; self.label = label; self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins; self.resetsAt = resetsAt
    }
    public var limit: LimitWindow { LimitWindow(usedPercent: usedPercent, windowDurationMins: windowDurationMins, resetsAt: resetsAt) }
}

public struct ProviderSnapshot: Codable, Sendable {
    public var provider: ProviderID
    public var plan: String?
    public var windows: [ProviderWindow]
    public var updatedAt: Date
    public var source: String
    public init(provider: ProviderID, plan: String?, windows: [ProviderWindow], updatedAt: Date = Date(), source: String) {
        self.provider = provider; self.plan = plan; self.windows = windows; self.updatedAt = updatedAt; self.source = source
    }
    public var headline: ProviderWindow? { windows.first { $0.windowDurationMins == 10080 && $0.label == nil } ?? windows.first { $0.windowDurationMins == 10080 } ?? windows.first }
    public func validated(at now: Date = Date()) throws -> Self {
        guard !windows.isEmpty, windows.count <= 16, source.count <= 80, (plan?.count ?? 0) <= 80,
              updatedAt.timeIntervalSince1970.isFinite,
              updatedAt <= now.addingTimeInterval(60), updatedAt > now.addingTimeInterval(-3600),
              Set(windows.map(\.id)).count == windows.count else { throw ProviderError.invalidData }
        for window in windows {
            guard !window.id.isEmpty, window.id.count <= 80, (window.label?.count ?? 0) <= 80 else { throw ProviderError.invalidData }
            if let used = window.usedPercent { guard used.isFinite && (0...100).contains(used) else { throw ProviderError.invalidData } }
            if let duration = window.windowDurationMins { guard duration > 0 && duration <= 525600 else { throw ProviderError.invalidData } }
            if let reset = window.resetsAt { guard reset.isFinite && reset > 0 else { throw ProviderError.invalidData } }
        }
        return self
    }
    public static func codex(_ response: LimitsResponse, at now: Date = Date()) -> Self {
        let buckets = response.buckets
        let windows = buckets.flatMap { entry in entry.bucket.windows.enumerated().map { index, window in
            ProviderWindow(id: "\(entry.id)-\(index)", label: entry.id == "codex" ? nil : (entry.bucket.limitName ?? entry.id), usedPercent: window.usedPercent, windowDurationMins: window.windowDurationMins, resetsAt: window.resetsAt)
        } }
        return Self(provider: .codex, plan: buckets.first?.bucket.planType, windows: windows, updatedAt: now, source: "Codex app-server")
    }
    /// Loopback protocol v1 uses Unix seconds, unlike JSONDecoder's default Date epoch.
    public static func decodeBridge(_ data: Data, at now: Date = Date()) throws -> Self {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(Self.self, from: data).validated(at: now)
        guard snapshot.provider == .gemini || snapshot.provider == .claude else { throw ProviderError.invalidData }
        return snapshot
    }
}

public enum ProviderError: Error, LocalizedError {
    case invalidData
    public var errorDescription: String? { "Usage data did not match the expected format." }
}
