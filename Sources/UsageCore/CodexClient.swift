import Foundation
import Darwin

public struct CodexClient: Sendable {
    public init() {}

    public static func discover(override: String? = nil) -> String? {
        let fm = FileManager.default
        if let override, !override.isEmpty {
            return fm.isExecutableFile(atPath: override) ? override : nil
        }
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            ProcessInfo.processInfo.environment["CODEX_BINARY_PATH"],
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "\(home)/.local/bin/codex", "\(home)/.npm-global/bin/codex"
        ].compactMap { $0 }
        return (candidates + (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { "\($0)/codex" }).first { fm.isExecutableFile(atPath: $0) }
    }

    // Run on a background executor. This client never reads credentials or conversations.
    public func fetch(binary: String, timeout: TimeInterval = 20) throws -> LimitsResponse {
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["app-server", "-c", "analytics.enabled=false"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        do { try process.run() } catch { throw UsageError.launch }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            let stop = ProcessInfo.processInfo.systemUptime + 1
            while process.isRunning && ProcessInfo.processInfo.systemUptime < stop { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        func send(_ value: [String: Any]) throws {
            var bytes = try JSONSerialization.data(withJSONObject: value)
            bytes.append(10)
            do { try input.fileHandleForWriting.write(contentsOf: bytes) }
            catch { throw UsageError.disconnected }
        }
        try send(["id": 0, "method": "initialize", "params": ["clientInfo": [
            "name": "chatgpt_usage", "title": "ChatGPT Usage", "version": "0.1.0"
        ]]])
        let fd = output.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        var pending = Data()
        var didInitialize = false
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 { if errno == EINTR { continue }; throw UsageError.disconnected }
            if ready == 0 { continue }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { throw UsageError.disconnected }
            if count < 0 { if errno == EAGAIN || errno == EINTR { continue }; throw UsageError.disconnected }
            pending.append(contentsOf: buffer.prefix(count))
            guard pending.count < 2_000_000 else { throw UsageError.protocolError }
            while let newline = pending.firstIndex(of: 10) {
                let line = pending[..<newline]
                pending.removeSubrange(...newline)
                guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                guard let id = obj["id"] as? Int else { continue } // Notifications do not complete a request.
                guard id == 0 || id == 1 else { continue }
                if let error = obj["error"] as? [String: Any] {
                    throw UsageError.unavailable(error["code"] as? Int ?? -1)
                }
                if id == 0 && !didInitialize {
                    guard obj["result"] != nil else { throw UsageError.protocolError }
                    didInitialize = true
                    try send(["method": "initialized", "params": [:]])
                    try send(["id": 1, "method": "account/rateLimits/read"])
                } else if id == 1 && didInitialize {
                    guard let result = obj["result"] as? [String: Any] else { throw UsageError.protocolError }
                    do {
                        let parsed = try LimitsResponse.decode(JSONSerialization.data(withJSONObject: result))
                        guard parsed.buckets.contains(where: { !$0.bucket.windows.isEmpty }) else { throw UsageError.noLimits }
                        return parsed
                    } catch let error as UsageError { throw error }
                    catch { throw UsageError.protocolError }
                }
            }
        }
        throw UsageError.timeout
    }
}
