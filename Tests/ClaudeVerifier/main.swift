import Foundation
import UsageCore
import Darwin

var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ name: String) {
    guard value() else { fatalError("FAIL: \(name)") }
    checks += 1
    print("PASS: \(name)")
}
func decode(_ json: String) throws -> ProviderSnapshot { try ClaudeClient.decodeUsage(Data(json.utf8)) }
func rejects(_ json: String) -> Bool { do { _ = try decode(json); return false } catch { return true } }

let body = #"{"rate_limits_available":true,"subscription_type":"pro","rate_limits":{"five_hour":{"utilization":0,"resets_at":"2026-10-17T13:14:15.123456Z"},"seven_day":{"utilization":31.5,"resets_at":"2026-10-20T13:14:15Z"},"model_scoped":[{"display_name":"Fable","utilization":42.2,"resets_at":null}]},"behaviors":null}"#
let snapshot = try decode(body)
expect(snapshot.provider == .claude && snapshot.plan == "pro", "Claude account metadata stays in its provider")
expect(snapshot.windows.count == 3, "session, weekly and scoped weekly quotas are retained")
expect(snapshot.windows[0].usedPercent == 0, "reported zero is a real measurement")
expect(snapshot.windows[1].usedPercent == 31.5, "fractional percent precision is preserved")
expect(snapshot.windows[0].resetsAt != nil && snapshot.windows[1].resetsAt != nil, "fractional and ordinary ISO reset timestamps parse")
expect(snapshot.windows[2].label == "Fable" && snapshot.windows[2].resetsAt == nil, "model title survives without invented reset time")
let envelope = "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"usage\",\"response\":\(body)}}"
let wrapped = try decode(envelope)
expect(wrapped.windows == snapshot.windows, "structured control envelope decodes")
expect(rejects(#"{"rate_limits_available":true,"rate_limits":null}"#), "unavailable live limits never become zero")
expect(rejects(#"{"rate_limits_available":false,"rate_limits":{"five_hour":{"utilization":10}}}"#), "inapplicable subscription limits stay unavailable")
expect(rejects(#"{"rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":null}}}"#), "unmeasured windows stay unavailable")
expect(rejects(#"{"rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":true}}}"#), "boolean utilization is rejected")
expect(rejects(#"{"rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":101}}}"#), "invalid percentages are rejected")
let typed = try decode(#"{"rate_limits_available":true,"rate_limits":{"limits":[{"kind":"session","percent":15,"resets_at":"invalid"},{"kind":"weekly_all","percent":20},{"kind":"weekly_scoped","percent":25,"scope":{"model":{"display_name":"Fable"}}},{"kind":"unknown","percent":99}]}}"#)
expect(typed.windows.count == 3 && typed.windows[0].resetsAt == nil, "typed server rows retain only understood windows and valid resets")
let deduped = try decode(#"{"rate_limits_available":true,"rate_limits":{"seven_day":{"utilization":20},"limits":[{"kind":"weekly_all","percent":20}]}}"#)
expect(deduped.windows.count == 1, "compatibility and typed rows do not duplicate the same quota")

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claude-verifier-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: directory) }
let fake = directory.appendingPathComponent("claude")
let script = #"""
#!/usr/bin/env python3
import sys, json, os
args = sys.argv[1:]
assert '--safe-mode' in args and '--no-session-persistence' in args and '--strict-mcp-config' in args
assert args[args.index('--tools') + 1] == ''
assert os.environ.get('DISABLE_AUTOUPDATER') == '1'
assert os.path.basename(os.getcwd()).startswith('usage-claude-')
first = json.loads(sys.stdin.readline())
assert first == {'type':'control_request','request_id':'init','request':{'subtype':'initialize'}}
print(json.dumps({'type':'system','subtype':'init','request_id':'init'}), flush=True)
print(json.dumps({'type':'control_response','response':{'subtype':'success','request_id':'irrelevant','response':{}}}), flush=True)
print(json.dumps({'type':'control_response','response':{'subtype':'success','request_id':'init','response':{}}}), flush=True)
second = json.loads(sys.stdin.readline())
assert second == {'type':'control_request','request_id':'usage','request':{'subtype':'get_usage','skip_behaviors':True}}
print(json.dumps({'type':'control_response','response':{'subtype':'success','request_id':'usage','response':{'rate_limits_available':True,'subscription_type':'pro','rate_limits':{'seven_day':{'utilization':9.5}}}}}), flush=True)
"""#
try script.write(to: fake, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
let result = try ClaudeClient().fetch(binary: fake.path, timeout: 5)
expect(result.windows.first?.usedPercent == 9.5, "passive handshake ignores notifications and requests only usage with transcript scans disabled")

let hanging = directory.appendingPathComponent("hanging-claude")
let marker = directory.appendingPathComponent("child-pid")
let hangingScript = "#!/usr/bin/env python3\nimport os,signal,time\nopen('\(marker.path)','w').write(str(os.getpid()))\nsignal.signal(signal.SIGTERM,signal.SIG_IGN)\ntime.sleep(30)\n"
try hangingScript.write(to: hanging, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hanging.path)
let started = ProcessInfo.processInfo.systemUptime
var timedOut = false
do { _ = try ClaudeClient().fetch(binary: hanging.path, timeout: 3) }
catch ClaudeClientError.timeout { timedOut = true }
catch { fatalError("Unexpected timeout test result: \(error)") }
let pid = Int32(try String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
expect(timedOut && ProcessInfo.processInfo.systemUptime - started < 6, "unresponsive child has a bounded timeout and cleanup")
expect(kill(pid, 0) == -1 && errno == ESRCH, "timeout cleanup reaps its own child process")
print("\(checks) Claude checks passed")
