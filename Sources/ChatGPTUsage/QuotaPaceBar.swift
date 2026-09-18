import SwiftUI
import UsageCore

struct QuotaPaceBar: View {
    let remaining: Double
    let pace: Pace?
    let weekly: Bool
    let korean: Bool
    private let accent = Color(red: 0.23, green: 0.75, blue: 0.62)
    private func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
    private var comparison: String {
        guard let pace else { return "" }
        let difference = pace.quotaAheadPercentagePoints
        if abs(difference) < 0.05 {
            return korean ? "균등 사용 페이스와 같아요" : "On the even-use pace"
        }
        let amount = percent(abs(difference))
        if difference > 0 {
            return korean ? "균등 페이스보다 \(amount)%p 여유" : "\(amount) pp more quota than the pace line"
        }
        return korean ? "균등 페이스보다 \(amount)%p 더 사용" : "\(amount) pp less quota than the pace line"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                        .frame(height: 7)
                    Capsule().fill(remaining <= 10 ? Color.orange : accent)
                        .frame(width: geometry.size.width * remaining / 100, height: 7)
                    if let pace {
                        // Both fill and marker count down from 100 to 0.
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.primary)
                            .frame(width: 3, height: 17)
                            .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1))
                            .offset(x: max(0, min(geometry.size.width - 3,
                                                 geometry.size.width * pace.remainingTimePercent / 100 - 1.5)))
                    }
                }.frame(height: 17)
            }.frame(height: 17)
            if let pace {
                HStack {
                    Text(korean ? "한도 \(percent(remaining))% 남음" : "Quota left \(percent(remaining))%")
                        .foregroundStyle(accent)
                    Spacer(minLength: 4)
                    Text(korean ? "│ 시간 \(percent(pace.remainingTimePercent))% 남음" : "│ Time left \(percent(pace.remainingTimePercent))%")
                        .foregroundStyle(.secondary)
                }.font(.system(size: 10)).monospacedDigit()
                Text(korean
                     ? "\(weekly ? "주간" : "기간") 시간 \(percent(pace.elapsedPercent))% 경과"
                     : "\(percent(pace.elapsedPercent))% of the \(weekly ? "week" : "window") elapsed")
                    .font(.caption).foregroundStyle(.secondary)
                Text(comparison)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(pace.quotaAheadPercentagePoints < -0.05 ? Color.orange : accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(korean ? "남은 한도와 시간 페이스" : "Remaining quota and time pace")
        .accessibilityValue(pace.map {
            korean
                ? "한도 \(percent(remaining))% 남음, 시간 \(percent($0.elapsedPercent))% 경과, \(percent($0.remainingTimePercent))% 남음. \(comparison)"
                : "Quota \(percent(remaining))% remaining, time \(percent($0.elapsedPercent))% elapsed, \(percent($0.remainingTimePercent))% remaining. \(comparison)"
        } ?? (korean ? "한도 \(percent(remaining))% 남음" : "Quota \(percent(remaining))% remaining"))
        .help(korean ? "세로선은 남은 시간 비율입니다. 한도 막대가 선보다 길면 균등 사용 기준보다 여유가 있습니다. 참고 기준이며 실제 일일 한도는 아닙니다."
              : "The vertical line marks time remaining. A longer quota bar means you are spending more slowly than an even-use pace. A reference, not an official daily limit.")
    }
}
