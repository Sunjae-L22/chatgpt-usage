import Foundation

public struct LimitWindow: Codable, Equatable, Sendable {
    public var usedPercent: Double?
    public var windowDurationMins: Int?
    public var resetsAt: Double?

    public var remaining: Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return max(0, min(100, 100 - usedPercent))
    }
    public var resetDate: Date? {
        guard let resetsAt, resetsAt.isFinite, resetsAt > 0 else { return nil }
        return Date(timeIntervalSince1970: resetsAt)
    }
    public var duration: TimeInterval? {
        guard let windowDurationMins, windowDurationMins > 0 else { return nil }
        return Double(windowDurationMins) * 60
    }
    // A straight-line reference, not a prediction or an official daily quota.
    public func pace(at now: Date) -> Pace? {
        guard let duration, let resetDate, let remaining,
              resetDate > now, resetDate.timeIntervalSince(now) <= duration else { return nil }
        let secondsLeft = resetDate.timeIntervalSince(now)
        let elapsed = 100 * (1 - secondsLeft / duration)
        return Pace(elapsedPercent: elapsed, usedMinusElapsed: (100 - remaining) - elapsed,
                    percentagePointsPerDay: remaining / (secondsLeft / 86400))
    }
}

public struct Pace: Equatable, Sendable {
    public let elapsedPercent: Double
    public let usedMinusElapsed: Double
    public let percentagePointsPerDay: Double
}

public struct LimitBucket: Codable, Sendable {
    public var limitId: String?
    public var limitName: String?
    public var primary: LimitWindow?
    public var secondary: LimitWindow?
    public var planType: String?

    public var windows: [LimitWindow] {
        [primary, secondary].compactMap { $0 }.reduce(into: []) { out, value in
            if !out.contains(value) { out.append(value) }
        }.sorted { ($0.windowDurationMins ?? Int.max) < ($1.windowDurationMins ?? Int.max) }
    }
    public var headline: LimitWindow? {
        windows.first { $0.windowDurationMins == 10080 } ?? windows.last
    }
}

public struct LimitsResponse: Codable, Sendable {
    public var rateLimits: LimitBucket?
    public var rateLimitsByLimitId: [String: LimitBucket]?

    public var buckets: [(id: String, bucket: LimitBucket)] {
        if let map = rateLimitsByLimitId, !map.isEmpty {
            return map.keys.sorted { a, b in
                if a == "codex" { return b != "codex" }
                if b == "codex" { return false }
                return a < b
            }.map { ($0, map[$0]!) }
        }
        return rateLimits.map { [($0.limitId ?? "codex", $0)] } ?? []
    }
    public static func decode(_ data: Data) throws -> Self { try JSONDecoder().decode(Self.self, from: data) }
}

public enum UsageError: Error, LocalizedError {
    case missingBinary, launch, timeout, disconnected, protocolError, unavailable(Int), noLimits
    public var errorDescription: String? {
        switch self {
        case .missingBinary: return "Install Codex or ChatGPT for Mac, then sign in with your ChatGPT account."
        case .launch: return "Could not start Codex. Select the Codex executable in Settings."
        case .timeout: return "Codex did not respond within 20 seconds. Check your connection and try again."
        case .disconnected: return "Codex closed the connection. Update Codex and try again."
        case .protocolError: return "The Codex response could not be read. Update the app and Codex."
        case .unavailable: return "Usage is unavailable. Check your ChatGPT sign-in in Codex and retry."
        case .noLimits: return "This account did not return quota windows. API-key sessions may not expose subscription limits."
        }
    }
}
