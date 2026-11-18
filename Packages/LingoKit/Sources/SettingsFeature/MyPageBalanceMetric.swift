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
            isLoaded: balance.credits != nil, identifier: "me.credits")
    }
}

struct MyPageBalanceMetric: View {
    let title: String
    let value: String
    let isLoaded: Bool
    let identifier: String
    @ScaledMetric(relativeTo: .title2) private var hubBalanceHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(isLoaded ? .title2.weight(.semibold) : .subheadline.weight(.medium))
                .foregroundStyle(isLoaded ? Color.dsSceneTextPrimary : Color.dsSceneTextSecondary)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(minHeight: hubBalanceHeight, alignment: .bottomLeading)
            Text(title).font(.caption).foregroundStyle(Color.dsSceneTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(value)")
        .accessibilityIdentifier(identifier)
    }
}
