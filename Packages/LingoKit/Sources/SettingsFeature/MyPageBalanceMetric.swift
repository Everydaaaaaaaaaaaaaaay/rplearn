import BackendKit
import DesignSystem
import Observation
import SwiftUI

/// The hub's identity, navigation and photograph do not observe credit requests.
@MainActor @Observable
final class MyPageCreditBalance {
    private(set) var credits: BackendAccessSnapshot.Credits?
    private var creditsError: String?
    private var isLoadingCredits = false

    var displayValue: String {
        if let credits { return credits.remaining.formatted(.number.precision(.fractionLength(2))) }
        return isLoadingCredits ? "读取中" : creditsError == nil ? "—" : "暂未更新"
    }

    func reload(using accessClient: BackendClient?) async {
        guard let accessClient, !isLoadingCredits else { return }
        isLoadingCredits = true
        defer { isLoadingCredits = false }
        do {
            credits = try await accessClient.accessSnapshot().credits
            creditsError = nil
        } catch is CancellationError {
        } catch {
            creditsError = "积分暂时无法加载，请重试。"
        }
    }
}

struct MyPageCreditMetric: View {
    let balance: MyPageCreditBalance
    var body: some View {
        MyPageBalanceMetric(title: "AI 积分", value: balance.displayValue,
            isLoaded: balance.credits != nil, identifier: "me.credits", symbol: "sparkles", candy: .grape)
    }
}

struct MyPageBalanceMetric: View {
    let title: String
    let value: String
    let isLoaded: Bool
    let identifier: String
    let symbol: String
    let candy: PuffCandy
    @ScaledMetric(relativeTo: .title2) private var hubBalanceHeight: CGFloat = 28

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(candy.deep)
                .frame(width: 34, height: 34)
                .background(Puff.Palette.card, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(isLoaded ? .puff(.title3, .heavy) : .puff(.subheadline, .bold))
                    .foregroundStyle(isLoaded ? Puff.Palette.ink : Puff.Palette.inkSoft)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(minHeight: hubBalanceHeight, alignment: .leading)
                Text(title)
                    .font(.puff(.caption, .bold))
                    .foregroundStyle(Puff.Palette.inkSoft)
            }
        }
        .padding(Puff.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(candy.wash, in: RoundedRectangle(cornerRadius: Puff.Radius.medium, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(value)")
        .accessibilityIdentifier(identifier)
    }
}
