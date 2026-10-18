import Foundation
import CoreFoundation
import Darwin

public enum ClaudeClientError: Error, LocalizedError {
    case missingBinary, launch, timeout, disconnected, invalidResponse, unsupported, unavailable

    public var errorDescription: String? {
        switch self {
        case .missingBinary: return "Install Claude Code and sign in, or connect Claude in your browser."
        case .launch: return "Could not start Claude Code. Check its installation."
        case .timeout: return "Claude usage did not respond in time. Try again later."
        case .disconnected: return "Claude Code closed the usage connection. Update Claude Code and retry."
        case .invalidResponse: return "Claude usage returned an unsupported format. Update the app and Claude Code."
        case .unsupported: return "This Claude Code version does not support structured usage. Update it or connect your browser."
        case .unavailable: return "Claude did not return subscription usage. Check your Claude sign-in or connect your browser."
        }
    }
}

/// Uses Claude Code's local control protocol. No model prompt, token extraction, or transcript scan is performed.
public struct ClaudeClient: Sendable {
    public init() {}

    public static func discover() -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                          "\(home)/.npm-global/bin/claude"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/claude" }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// Run on a background executor. CLI owns authentication; this process only requests quota data.
    public func fetch(binary: String, timeout: TimeInterval = 20) throws -> ProviderSnapshot {
        guard timeout.isFinite, timeout > 0 else { throw ClaudeClientError.timeout }
        guard FileManager.default.isExecutableFile(atPath: binary) else { throw ClaudeClientError.missingBinary }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("usage-claude-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        catch { throw ClaudeClientError.launch }
        defer { try? FileManager.default.removeItem(at: directory) }

        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                             "--no-session-persistence", "--safe-mode", "--strict-mcp-config", "--tools", "",
                             "--settings", #"{"remoteControlAtStartup":false,"disableAllHooks":true}"#]
        var environment = ProcessInfo.processInfo.environment
        // A menu-bar quota probe must use the CLI's own subscription login, never an inherited API-key override.
        for key in Array(environment.keys) where key.hasPrefix("ANTHROPIC_") || key.hasPrefix("CLAUDE_CODE_OAUTH") || key.hasPrefix("CLAUDE_CODE_USE_") {
            environment.removeValue(forKey: key)
        }
        environment["DISABLE_AUTOUPDATER"] = "1"
        environment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = directory
        do { try process.run() } catch { throw ClaudeClientError.launch }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            let stop = ProcessInfo.processInfo.systemUptime + 0.5
            while process.isRunning && ProcessInfo.processInfo.systemUptime < stop { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        // A CLI that exits between its initialization reply and the usage request must not terminate our app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        func send(_ id: String, _ request: [String: Any]) throws {
            let message: [String: Any] = ["type": "control_request", "request_id": id, "request": request]
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(10)
            do { try input.fileHandleForWriting.write(contentsOf: data) }
            catch { throw ClaudeClientError.disconnected }
        }

        try send("init", ["subtype": "initialize"])
        let fd = output.fileHandleForReading.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else { throw ClaudeClientError.disconnected }
        var pending = Data(), receivedBytes = 0
        var initialized = false
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 { if errno == EINTR { continue }; throw ClaudeClientError.disconnected }
            if ready == 0 { continue }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { throw ClaudeClientError.disconnected }
            if count < 0 { if errno == EAGAIN || errno == EINTR { continue }; throw ClaudeClientError.disconnected }
            receivedBytes += count
            guard receivedBytes <= 2_000_000 else { throw ClaudeClientError.invalidResponse }
            pending.append(contentsOf: buffer.prefix(count))
            while let newline = pending.firstIndex(of: 10) {
                let line = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      message["type"] as? String == "control_response",
                      let response = message["response"] as? [String: Any],
                      let id = response["request_id"] as? String else { continue }
                guard id == "init" || (id == "usage" && initialized) else { continue }
                guard response["subtype"] as? String == "success" else { throw ClaudeClientError.unsupported }
                if id == "init" && !initialized {
                    initialized = true
                    try send("usage", ["subtype": "get_usage", "skip_behaviors": true])
                } else if id == "usage" {
                    return try Self.decodeUsage(line)
                }
            }
        }
        throw ClaudeClientError.timeout
    }

    /// Accepts a get_usage body or its successful control_response envelope. Missing values never become zero.
    public static func decodeUsage(_ data: Data) throws -> ProviderSnapshot {
        guard data.count <= 2_000_000,
              var body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ClaudeClientError.invalidResponse
        }
        if body["type"] as? String == "control_response" {
            guard let response = body["response"] as? [String: Any],
                  response["subtype"] as? String == "success",
                  let payload = response["response"] as? [String: Any] else { throw ClaudeClientError.invalidResponse }
            body = payload
        }
        guard body["rate_limits_available"] as? Bool == true,
              let limits = body["rate_limits"] as? [String: Any] else { throw ClaudeClientError.unavailable }

        var windows: [ProviderWindow] = []
        func add(id: String, label: String? = nil, percent: Any?, reset: Any?, minutes: Int) throws {
            guard let number = percent as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
                if percent == nil || percent is NSNull { return }
                throw ClaudeClientError.invalidResponse
            }
            let value = number.doubleValue
            guard value.isFinite, (0...100).contains(value), (label?.count ?? 0) <= 80 else { throw ClaudeClientError.invalidResponse }
            let date: Date?
            if let iso = reset as? String {
                let format = ISO8601DateFormatter()
                format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let fractional = format.date(from: iso)
                format.formatOptions = [.withInternetDateTime]
                date = fractional ?? format.date(from: iso)
            } else { date = nil }
            guard !windows.contains(where: { $0.id == id }) else { return }
            windows.append(ProviderWindow(id: id, label: label, usedPercent: value, windowDurationMins: minutes,
                                          resetsAt: date.flatMap { $0.timeIntervalSince1970 > 0 ? $0.timeIntervalSince1970 : nil }))
        }

        for (key, label, minutes) in [("five_hour", nil as String?, 300), ("seven_day", nil, 10080),
                                      ("seven_day_sonnet", "Sonnet", 10080), ("seven_day_opus", "Opus", 10080),
                                      ("seven_day_oauth_apps", "Connected apps", 10080)] {
            if let window = limits[key] as? [String: Any] {
                try add(id: key, label: label, percent: window["utilization"], reset: window["resets_at"], minutes: minutes)
            }
        }
        if let scoped = limits["model_scoped"] as? [[String: Any]] {
            for (index, window) in scoped.enumerated() {
                guard let label = window["display_name"] as? String, !label.isEmpty else { continue }
                if windows.contains(where: { $0.label == label && $0.windowDurationMins == 10080 }) { continue }
                try add(id: "model_scoped-\(index)", label: label, percent: window["utilization"], reset: window["resets_at"], minutes: 10080)
            }
        }
        // Current servers may carry their primary meters as typed rows alongside the older compatibility fields.
        if let rows = limits["limits"] as? [[String: Any]] {
            for (index, row) in rows.enumerated() {
                switch row["kind"] as? String {
                case "session": try add(id: "five_hour", percent: row["percent"], reset: row["resets_at"], minutes: 300)
                case "weekly_all": try add(id: "seven_day", percent: row["percent"], reset: row["resets_at"], minutes: 10080)
                case "weekly_scoped":
                    guard let scope = row["scope"] as? [String: Any], let model = scope["model"] as? [String: Any],
                          let label = model["display_name"] as? String, !label.isEmpty else { continue }
                    if windows.contains(where: { $0.label == label && $0.windowDurationMins == 10080 }) { continue }
                    try add(id: "weekly_scoped-\(index)", label: label, percent: row["percent"], reset: row["resets_at"], minutes: 10080)
                default: continue // Unknown types cannot safely be assigned an invented duration.
                }
            }
        }
        guard !windows.isEmpty else { throw ClaudeClientError.unavailable }
        let snapshot = ProviderSnapshot(provider: .claude, plan: body["subscription_type"] as? String,
                                        windows: windows, source: "Claude Code usage")
        do { return try snapshot.validated() } catch { throw ClaudeClientError.invalidResponse }
    }
}
