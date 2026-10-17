import Foundation
import Combine
import Network
import Security

/// Receives quota-only snapshots from the locally paired browser extension.
/// The pairing token belongs to this app; it is never an upstream account token.
@MainActor final class UsageBridge: ObservableObject {
    @Published private(set) var status = "Stopped"
    @Published private(set) var isRunning = false
    @Published private(set) var pairingToken: String
    let port: UInt16 = 49627
    private static let tokenKey = "usageBridgePairingToken"
    private let queue = DispatchQueue(label: "io.github.sunjae-l22.usage-bridge")
    private let tokenBox: BridgeTokenBox
    private var listener: NWListener?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.tokenKey)
        let token = saved.flatMap { $0.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil ? $0 : nil }
            ?? Self.newToken()
        pairingToken = token
        tokenBox = BridgeTokenBox(token)
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
    }

    func start(validate: ((Data) -> Bool)? = nil, onPayload: @escaping (Data) -> Void) {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = false
        do {
            let server = try NWListener(using: parameters)
            listener = server
            status = "Starting"
            server.stateUpdateHandler = { [weak self, weak server] state in
                Task { @MainActor in
                    guard let self, self.listener === server else { return }
                    switch state {
                    case .ready: self.isRunning = true; self.status = "Ready"
                    case .failed:
                        self.isRunning = false; self.status = "Could not open local connection"
                        server?.cancel(); self.listener = nil
                    case .cancelled: self.isRunning = false; self.status = "Stopped"
                    default: break
                    }
                }
            }
            let box = tokenBox
            let queue = queue
            server.newConnectionHandler = { connection in
                BridgeConnection(connection: connection, queue: queue, tokenBox: box) { data, complete in
                    Task { @MainActor in
                        let accepted = validate?(data) ?? true
                        if accepted { onPayload(data) }
                        complete(accepted)
                    }
                }.start()
            }
            server.start(queue: queue)
        } catch {
            status = "Could not open local connection"
            isRunning = false
        }
    }

    func rotateToken() {
        let token = Self.newToken()
        pairingToken = token
        tokenBox.set(token)
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
    }

    private static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess,
                     "Secure random generation is unavailable")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

private final class BridgeTokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String
    init(_ value: String) { self.value = value }
    func get() -> String { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ value: String) { lock.lock(); defer { lock.unlock() }; self.value = value }
}

struct BridgeRequest {
    let method: String
    let origin: String?
    let body: Data
}

enum BridgeParseResult {
    case incomplete
    case failure(Int, origin: String?)
    case request(BridgeRequest)
}

/// Strict one-request HTTP/1.1 parser. No chunked bodies, pipelining, or cookies.
enum BridgeHTTP {
    static let headerLimit = 8 * 1024
    static let bodyLimit = 64 * 1024

    static func isExtensionOrigin(_ origin: String) -> Bool {
        origin.range(of: "^chrome-extension://[a-p]{32}$", options: .regularExpression) != nil
    }

    static func tokensMatch(_ supplied: String, _ expected: String) -> Bool {
        let a = Array(supplied.utf8), b = Array(expected.utf8)
        // Token length is public; content comparison does not exit early.
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }

    static func parse(_ data: Data, token: String) -> BridgeParseResult {
        let delimiter = Data([13, 10, 13, 10])
        guard let boundary = data.range(of: delimiter) else {
            return data.count > headerLimit ? .failure(431, origin: nil) : .incomplete
        }
        guard boundary.upperBound <= headerLimit,
              let header = String(data: data[..<boundary.lowerBound], encoding: .utf8),
              !header.contains("\0") else { return .failure(431, origin: nil) }
        let lines = header.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: false)
        guard first.count == 3, first[2] == "HTTP/1.1" else { return .failure(400, origin: nil) }
        let method = String(first[0]), path = String(first[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .failure(400, origin: nil) }
            let key = String(line[..<colon]).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard key.range(of: "^[!#$%&'*+.^_`|~0-9a-z-]+$", options: .regularExpression) != nil,
                  !value.contains("\r"), !value.contains("\n"), headers[key] == nil else {
                return .failure(400, origin: nil)
            }
            headers[key] = value
        }
        let origin = headers["origin"]
        guard origin == nil || isExtensionOrigin(origin!) else { return .failure(403, origin: nil) }
        guard path == "/v1/usage" || path == "/v1/health" else { return .failure(404, origin: origin) }
        guard headers["transfer-encoding"] == nil else { return .failure(400, origin: origin) }
        let contentLength: Int
        if let length = headers["content-length"] {
            guard !length.isEmpty, length.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let parsed = Int(length), parsed <= bodyLimit else { return .failure(413, origin: origin) }
            contentLength = parsed
        } else {
            guard method != "POST" else { return .failure(411, origin: origin) }
            contentLength = 0
        }
        if method == "OPTIONS" {
            guard contentLength == 0, data.count == boundary.upperBound else { return .failure(400, origin: origin) }
            return .request(BridgeRequest(method: method, origin: origin, body: Data()))
        }
        guard (method == "POST" && path == "/v1/usage") || (method == "GET" && path == "/v1/health") else {
            return .failure(405, origin: origin)
        }
        guard let authorization = headers["authorization"], authorization.hasPrefix("Bearer "),
              tokensMatch(String(authorization.dropFirst(7)), token) else { return .failure(401, origin: origin) }
        if method == "POST" {
            let type = headers["content-type"]?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
            guard type == "application/json" else { return .failure(415, origin: origin) }
        } else if contentLength != 0 { return .failure(400, origin: origin) }
        let available = data.count - boundary.upperBound
        guard available <= contentLength else { return .failure(400, origin: origin) }
        guard available == contentLength else { return .incomplete }
        let body = Data(data[boundary.upperBound...])
        if method == "POST" {
            guard !body.isEmpty, (try? JSONSerialization.jsonObject(with: body)) is [String: Any] else {
                return .failure(400, origin: origin)
            }
        }
        return .request(BridgeRequest(method: method, origin: origin, body: body))
    }
}

private final class BridgeConnection {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let tokenBox: BridgeTokenBox
    private let onPayload: (Data, @escaping (Bool) -> Void) -> Void
    private var data = Data()
    private var deadline: DispatchWorkItem?
    private var finished = false

    init(connection: NWConnection, queue: DispatchQueue, tokenBox: BridgeTokenBox,
         onPayload: @escaping (Data, @escaping (Bool) -> Void) -> Void) {
        self.connection = connection; self.queue = queue
        self.tokenBox = tokenBox; self.onPayload = onPayload
    }
    func start() {
        // The receive closure owns this session until completion or cancellation.
        let timeout = DispatchWorkItem { [weak self] in self?.close() }
        deadline = timeout
        queue.asyncAfter(deadline: .now() + 10, execute: timeout)
        connection.start(queue: queue)
        receive()
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [self] chunk, _, complete, error in
            guard !finished else { return }
            if let chunk { data.append(chunk) }
            guard data.count <= BridgeHTTP.headerLimit + BridgeHTTP.bodyLimit else {
                respond(413, origin: nil); return
            }
            switch BridgeHTTP.parse(data, token: tokenBox.get()) {
            case .incomplete:
                if complete || error != nil { close() } else { receive() }
            case .failure(let code, let origin): respond(code, origin: origin)
            case .request(let request):
                if request.method == "POST" {
                    onPayload(request.body) { [self] accepted in
                        queue.async { [self] in respond(accepted ? 200 : 422, origin: request.origin) }
                    }
                } else {
                    respond(request.method == "OPTIONS" ? 204 : 200, origin: request.origin)
                }
            }
        }
    }
    private func respond(_ code: Int, origin: String?) {
        guard !finished else { return }
        finished = true
        deadline?.cancel(); deadline = nil
        let labels = [200: "OK", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
                      404: "Not Found", 405: "Method Not Allowed", 411: "Length Required", 413: "Content Too Large",
                      415: "Unsupported Media Type", 422: "Unprocessable Content", 431: "Request Header Fields Too Large"]
        let body = code == 204 ? "" : (code == 200 ? "{\"ok\":true}" : "{\"ok\":false,\"status\":\(code)}")
        var response = "HTTP/1.1 \(code) \(labels[code] ?? "Error")\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\nCache-Control: no-store\r\n"
        if let origin, BridgeHTTP.isExtensionOrigin(origin) {
            response += "Access-Control-Allow-Origin: \(origin)\r\nVary: Origin\r\n"
            if code == 204 {
                response += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Authorization, Content-Type\r\nAccess-Control-Max-Age: 600\r\nAccess-Control-Allow-Private-Network: true\r\n"
            }
        }
        response += "\r\n" + body
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [self] _ in connection.cancel() })
    }
    private func close() {
        finished = true; deadline?.cancel(); deadline = nil; connection.cancel()
    }
}
