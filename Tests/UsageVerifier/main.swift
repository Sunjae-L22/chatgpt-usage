import Foundation
import UsageCore

setbuf(stdout, nil)
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    checks += 1
    print("PASS: \(message)")
}
func decode(_ json: String) throws -> LimitsResponse { try LimitsResponse.decode(Data(json.utf8)) }
let weekly = #"{"usedPercent":49,"windowDurationMins":10080,"resetsAt":2000604800}"#
let short = #"{"usedPercent":10,"windowDurationMins":300,"resetsAt":2000018000}"#
let onlyWeekly = try decode("{\"rateLimits\":{\"primary\":\(weekly),\"secondary\":null,\"planType\":\"prolite\"}}")
check(onlyWeekly.buckets[0].bucket.windows.count == 1, "Weekly-only account has exactly one window")
check(onlyWeekly.buckets[0].bucket.headline?.windowDurationMins == 10080, "Weekly can occupy primary")
check(onlyWeekly.buckets[0].bucket.headline?.remaining == 51, "Used 49 means remaining 51")
let two = try decode("{\"rateLimits\":{\"primary\":\(short),\"secondary\":\(weekly)}}")
check(two.buckets[0].bucket.windows.map(\.windowDurationMins) == [300,10080], "Two windows preserve actual durations")
check(two.buckets[0].bucket.headline?.windowDurationMins == 10080, "Headline picks weekly by duration")
let multi = try decode("{\"rateLimits\":{\"primary\":\(short)},\"rateLimitsByLimitId\":{\"spark\":{\"primary\":\(short)},\"codex\":{\"primary\":\(weekly)}}}")
check(multi.buckets.map(\.id) == ["codex","spark"], "Multi-bucket response wins over legacy and sorts Codex first")
check(multi.buckets[0].bucket.windows.count == 1, "Does not invent a short window from another bucket")
let emptyMap = try decode("{\"rateLimitsByLimitId\":{},\"rateLimits\":{\"primary\":\(weekly)}}")
check(emptyMap.buckets.count == 1, "Empty map falls back to legacy")
let missing = try decode(#"{"rateLimits":{"primary":{"usedPercent":null,"windowDurationMins":null,"resetsAt":null}}}"#).buckets[0].bucket.windows[0]
check(missing.remaining == nil && missing.duration == nil && missing.resetDate == nil, "Missing values stay unknown")
let clamp = try decode(#"{"rateLimits":{"primary":{"usedPercent":110},"secondary":{"usedPercent":-8}}}"#).buckets[0].bucket.windows
check(clamp.map(\.remaining) == [0,100], "Remaining display clamps out-of-range percentages")
let window = onlyWeekly.buckets[0].bucket.windows[0]
let half = Date(timeIntervalSince1970: 2000302400)
let pace = window.pace(at: half)!
check(abs(pace.elapsedPercent - 50) < 0.001, "Pacing uses actual window length and reset")
check(abs(pace.percentagePointsPerDay - 51/3.5) < 0.001, "Daily reference divides remaining quota by remaining days")
check(window.pace(at: Date(timeIntervalSince1970: 2000604800)) == nil, "Expired reset does not fabricate new quota")
check(window.pace(at: Date(timeIntervalSince1970: 1999999999)) == nil, "Inconsistent future window does not produce pacing")
let duplicate = try decode("{\"rateLimits\":{\"primary\":\(weekly),\"secondary\":\(weekly)}}")
check(duplicate.buckets[0].bucket.windows.count == 1, "Duplicate windows are not shown twice")
check(CodexClient.discover(override: "/not/a/codex") == nil, "Invalid explicit binary does not silently use another account source")

let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
func fake(_ name: String, _ script: String) throws -> String {
    let path = directory.appendingPathComponent(name)
    try ("#!/bin/sh\n" + script).write(to: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    return path.path
}
let success = try fake("success", """
IFS= read -r request
case "$request" in *initialize*) ;; *) exit 1;; esac
printf '%s\\n' '{"id":0,"result":{}}'
IFS= read -r initialized
case "$initialized" in *initialized*) ;; *) exit 1;; esac
IFS= read -r limits
case "$limits" in *account*rateLimits*read*) ;; *) exit 1;; esac
printf '%s\\n' '{"method":"notice","params":{}}'
printf '%s' '{"id":1,"result":'
printf '%s\\n' '{"rateLimits":{"primary":{"usedPercent":49,"windowDurationMins":10080}}}}'
IFS= read -r end
""")
let result = try CodexClient().fetch(binary: success, timeout: 2)
check(result.buckets[0].bucket.headline?.remaining == 51, "Protocol handshake, notifications, and split response work")
let failure = try fake("failure", """
IFS= read -r request
printf '%s\\n' '{"id":0,"error":{"code":401,"message":"private server detail"}}'
""")
do { _ = try CodexClient().fetch(binary: failure, timeout: 1); check(false, "Error expected") }
catch { check(!error.localizedDescription.contains("private server detail"), "Server errors are sanitized") }
let hang = try fake("hang", "while IFS= read -r request; do :; done\n")
let began = Date()
do { _ = try CodexClient().fetch(binary: hang, timeout: 0.2); check(false, "Timeout expected") }
catch { check(Date().timeIntervalSince(began) < 3, "Timeout terminates child process promptly") }
let closed = try fake("closed", "exit 0\n")
do { _ = try CodexClient().fetch(binary: closed, timeout: 1); check(false, "Disconnect expected") }
catch { check(true, "Early subprocess exit is reported") }
print("\(checks) checks passed")
