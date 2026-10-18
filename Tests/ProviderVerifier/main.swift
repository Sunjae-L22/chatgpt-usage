import Foundation
import UsageCore

var checks = 0
func check(_ condition: Bool, _ name: String) {
    guard condition else { fatalError(name) }; checks += 1; print("PASS: \(name)")
}
let now = Date()
func payload(_ windows: String, provider: String = "gemini", updated: Double = now.timeIntervalSince1970) -> Data {
    Data("""
    {"provider":"\(provider)","plan":null,"source":"Gemini web","updatedAt":\(updated),"windows":\(windows)}
    """.utf8)
}
let sample = #"[{"id":"weekly","usedPercent":42.5,"windowDurationMins":10080,"resetsAt":2000000000}]"#
let snapshot = try ProviderSnapshot.decodeBridge(payload(sample), at: now)
check(snapshot.windows[0].limit.remaining == 57.5, "Preserves genuine fractional percentages")
check(abs(snapshot.updatedAt.timeIntervalSince1970 - now.timeIntervalSince1970) < 0.001, "Bridge uses Unix seconds")
check((try? ProviderSnapshot.decodeBridge(payload(sample, provider: "codex"), at: now)) == nil, "Bridge cannot replace local Codex source")
check((try? ProviderSnapshot.decodeBridge(payload(sample, updated: now.addingTimeInterval(61).timeIntervalSince1970), at: now)) == nil, "Rejects future timestamps")
check((try? ProviderSnapshot.decodeBridge(payload(sample, updated: now.addingTimeInterval(-3601).timeIntervalSince1970), at: now)) == nil, "Rejects old snapshots")
for value in ["-1", "101", "true", "\"25\""] {
    check((try? ProviderSnapshot.decodeBridge(payload("[{\"id\":\"weekly\",\"usedPercent\":\(value)}]"), at: now)) == nil, "Rejects invalid percent \(value)")
}
let missing = try ProviderSnapshot.decodeBridge(payload(#"[{"id":"weekly","usedPercent":null}]"#), at: now)
check(missing.windows[0].limit.remaining == nil, "Missing quota remains unknown")
check((try? ProviderSnapshot.decodeBridge(payload(#"[{"id":"x"},{"id":"x"}]"#), at: now)) == nil, "Rejects duplicate IDs")
let codex = try LimitsResponse.decode(Data(#"{"rateLimits":{"planType":"pro","primary":{"usedPercent":42,"windowDurationMins":10080}}}"#.utf8))
check(ProviderSnapshot.codex(codex).headline?.limit.remaining == 58, "Codex normalization preserves quota")
print("\(checks) provider checks passed")
