import Foundation

let token = String(repeating: "a", count: 64)
let origin = "chrome-extension://" + String(repeating: "b", count: 32)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    checks += 1; print("PASS: \(message)")
}
func request(_ method: String = "POST", path: String = "/v1/usage", extra: [String] = [],
             body: String = "{\"provider\":\"gemini\"}", auth: Bool = true, withOrigin: Bool = true) -> Data {
    var lines = ["\(method) \(path) HTTP/1.1", "Host: 127.0.0.1:49627"]
    if auth { lines.append("Authorization: Bearer \(token)") }
    if withOrigin { lines.append("Origin: \(origin)") }
    lines += extra
    if method == "POST" { lines += ["Content-Type: application/json", "Content-Length: \(body.utf8.count)"] }
    return Data((lines.joined(separator: "\r\n") + "\r\n\r\n" + (method == "POST" ? body : "")).utf8)
}
func status(_ data: Data, expectedToken: String = token) -> Int {
    switch BridgeHTTP.parse(data, token: expectedToken) {
    case .incomplete: return 0
    case .failure(let code, _): return code
    case .request(let request): return request.method == "OPTIONS" ? 204 : 200
    }
}
check(status(request()) == 200, "Paired extension JSON quota is accepted")
check(status(request(withOrigin: false)) == 200, "Native loopback requests can omit Origin")
check(status(request(auth: false)) == 401, "Usage requires a pairing token")
check(status(request(), expectedToken: String(repeating: "b", count: 64)) == 401, "Wrong pairing token is rejected")
check(status(request("GET", path: "/v1/health", auth: false)) == 401, "Health also requires pairing")
check(status(request("GET", path: "/v1/health")) == 200, "Authenticated health is accepted")
check(status(request("OPTIONS", auth: false)) == 204, "Extension preflight does not need authorization")
check(status(request(extra: ["Origin: https://example.com"])) == 400, "Duplicate Origin is rejected")
let evil = String(decoding: request(), as: UTF8.self).replacingOccurrences(of: origin, with: "https://example.com")
check(status(Data(evil.utf8)) == 403, "Web page origins cannot submit usage")
check(!BridgeHTTP.isExtensionOrigin(origin + "/path") && !BridgeHTTP.isExtensionOrigin("chrome-extension://short"), "Extension origin syntax is exact")
check(status(request(path: "/unexpected")) == 404, "Unknown routes are rejected")
check(status(request("GET", path: "/v1/usage")) == 405, "Routes enforce their methods")
check(status(request(extra: ["Transfer-Encoding: chunked"])) == 400, "Chunked encoding is rejected")
check(status(request(extra: ["Content-Length: 1"])) == 400, "Duplicate Content-Length is rejected")
check(status(request(body: "not json")) == 400, "Malformed JSON is rejected")
check(status(request(body: "[]")) == 400, "Payload must be a JSON object")
let full = request()
check(status(Data(full.dropLast())) == 0, "Partial JSON body waits for remaining bytes")
check(status(full + Data("x".utf8)) == 400, "Extra bytes and pipelined requests are rejected")
check(status(Data(String(repeating: "X", count: 8193).utf8)) == 431, "Header limit is enforced before delimiter")
check(status(request(body: "{\"data\":\"" + String(repeating: "x", count: 65536) + "\"}")) == 413, "Body limit is enforced from Content-Length")
let noLength = "POST /v1/usage HTTP/1.1\r\nAuthorization: Bearer \(token)\r\n\r\n{}"
check(status(Data(noLength.utf8)) == 411, "POST requires Content-Length")
let badType = String(decoding: request(), as: UTF8.self).replacingOccurrences(of: "application/json", with: "text/plain")
check(status(Data(badType.utf8)) == 415, "POST requires application/json")
check(BridgeHTTP.tokensMatch(token, token) && !BridgeHTTP.tokensMatch(token, "a"), "Token comparison checks full token")
print("\(checks) bridge checks passed")

// Optional local integration harness. Never print the pairing token or payload.
if CommandLine.arguments.contains("--serve") {
    Task { @MainActor in
        let bridge = UsageBridge()
        UserDefaults.standard.synchronize()
        bridge.start(validate: { data in
            guard Thread.isMainThread,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return object["provider"] as? String == "gemini" && object["quotas"] is [Any]
        }) { data in
            print("ACCEPTED \(data.count) bytes on main thread: \(Thread.isMainThread)")
            fflush(stdout)
        }
        print("Bridge integration harness started")
        fflush(stdout)
        while true {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            _ = bridge.isRunning // Keep the listener alive for integration requests.
        }
    }
    RunLoop.main.run()
}
