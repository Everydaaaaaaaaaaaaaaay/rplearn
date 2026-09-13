import BillingKit
import DesignSystem
import PersistenceKit
import SwiftUI

/// 会员购买页：权益、真实商店价格和单一购买入口。
struct SubscriptionView: View {
    let billing: BillingController
    @State private var selectedProductID: String?
    @State private var managementError: String?
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var products: [PurchasableProduct] {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_SUBSCRIPTION_PRICES"] == "1" {
            return [
                PurchasableProduct(ticketCount: 1, displayName: "Plus", displayPrice: "¥39.00",
                    periodDescription: "每月", productDescription: "界面预览", productID: "preview.plus.monthly", tier: .plus),
                PurchasableProduct(ticketCount: 2, displayName: "Pro", displayPrice: "¥59.00",
                    periodDescription: "每月", productDescription: "界面预览", productID: "preview.pro.monthly", tier: .pro)
            ]
        }
        #endif
        return billing.offeredProducts
    }

    private var usesPreviewPrices: Bool { selectedProduct?.productID.hasPrefix("preview.") == true }

    private var selectedProduct: PurchasableProduct? {
        products.first { $0.id == selectedProductID }
            ?? products.first { $0.tier == .plus }
            ?? products.first
    }

    private var busy: Bool { billing.operation != .idle }
    private var isCurrentPlan: Bool {
        guard let selectedProduct else { return false }
        return billing.tier == selectedProduct.tier
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introduction
                benefits
                plans
                if let error = billing.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("subscription.error")
                }
                if let message = billing.message {
                    Text(message).font(.footnote).foregroundStyle(Color.dsPaperInkSecondary)
                }
                HStack(spacing: 24) {
                    Button("恢复购买") { Task { await billing.restorePurchases() } }
                        .disabled(busy)
                        .accessibilityIdentifier("subscription.restore")
                    Button("管理订阅", action: manageSubscription)
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("subscription.content")
        .foregroundStyle(Color.dsPaperInk)
        .tint(.dsTravelNavy)
        .safeAreaInset(edge: .bottom, spacing: 0) { purchaseDock }
        .background {
            DSWorkbenchBackdrop(focus: .subscription)
            LinearGradient(
                stops: [
                    .init(color: paperTone.opacity(reduceTransparency ? 1 : 0.94), location: 0),
                    .init(color: paperTone.opacity(reduceTransparency ? 1 : 0.88), location: 0.26),
                    .init(color: paperTone.opacity(reduceTransparency ? 1 : 0.18), location: 0.48),
                    .init(color: paperTone.opacity(reduceTransparency ? 1 : 0.12), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .task { await billing.synchronize(showLoading: true) }
        .alert("无法打开订阅管理", isPresented: Binding(
            get: { managementError != nil }, set: { if !$0 { managementError = nil } }
        )) { Button("好", role: .cancel) {} } message: { Text(managementError ?? "") }
    }

    private var paperTone: Color { Color(red: 0.985, green: 0.970, blue: 0.925) }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("咕游记会员")
                .font(.title2.bold())
            Text("认识更多朋友，让每次交流更进一步。")
                .font(.subheadline).foregroundStyle(Color.dsPaperInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if billing.tier != .free {
                Text("当前会员：\(billing.tier.displayName)")
                    .font(.subheadline.weight(.medium))
                if let validity = billing.currentValidityDescription {
                    Text(validity).font(.footnote).foregroundStyle(Color.dsPaperInkSecondary)
                }
            }
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 10) {
            benefit("person.2", "更多旅途朋友")
            benefit("text.bubble", "更连贯的对话")
            benefit("heart.text.clipboard", "更长久的记忆")
        }
    }

    private func benefit(_ symbol: String, _ title: String) -> some View {
        Label {
            Text(title).font(.subheadline)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.dsTravelNavy)
                .frame(width: 24)
        }
    }

    private var plans: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选择会员方案").font(.headline).padding(.bottom, 10)
            if products.isEmpty {
                if billing.operation == .loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在获取 App Store 价格…")
                    }
                    .font(.subheadline).foregroundStyle(Color.dsPaperInkSecondary)
                } else {
                    Text("暂时无法获取订阅价格")
                        .font(.subheadline).foregroundStyle(Color.dsPaperInkSecondary)
                    Button("重新加载") { Task { await billing.synchronize(showLoading: true) } }
                        .font(.subheadline.weight(.medium))
                        .padding(.top, 12)
                        .accessibilityIdentifier("subscription.reload")
                }
            } else {
                Divider()
                ForEach(products) { product in
                    plan(product)
                    Divider()
                }
            }
        }
    }

    private func plan(_ product: PurchasableProduct) -> some View {
        Button {
            selectedProductID = product.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedProduct?.id == product.id ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedProduct?.id == product.id ? Color.dsTravelNavy : Color.dsPaperInkSecondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(product.tier.displayName).font(.title3.bold())
                        Spacer(minLength: 8)
                        Text(product.checkoutDisplayPrice).font(.headline.monospacedDigit())
                    }
                    Text(product.tier == .pro ? "更深入的陪伴，适合高频交流" : "开启更多交流，适合日常练习")
                        .font(.subheadline).foregroundStyle(Color.dsPaperInkSecondary)
                    if product.ticketCount > 0 {
                        Text("每个付费周期含 \(product.ticketCount) 张通用机票")
                            .font(.footnote).foregroundStyle(Color.dsPaperInkSecondary)
                    }
                    if let detail = product.checkoutPriceDetail {
                        Text(detail).font(.footnote).foregroundStyle(Color.dsPaperInkSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityAddTraits(selectedProduct?.id == product.id ? .isSelected : [])
        .accessibilityIdentifier("subscription.plan.\(product.tier.rawValue)")
    }

    private var purchaseDock: some View {
        VStack(spacing: 10) {
            Button {
                if isCurrentPlan {
                    manageSubscription()
                } else if let selectedProduct, !usesPreviewPrices {
                    Task { await billing.purchase(selectedProduct) }
                }
            } label: {
                HStack(spacing: 10) {
                    if busy { ProgressView().tint(.white) }
                    Text(isCurrentPlan ? "管理当前订阅" : selectedProduct.map { "订阅 \($0.tier.displayName)" } ?? "订阅会员")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.dsWorkbenchAction)
            .disabled(usesPreviewPrices || busy || selectedProduct == nil || (!isCurrentPlan && !billing.purchasesEnabled))
            .opacity(busy || selectedProduct == nil || (!isCurrentPlan && !billing.purchasesEnabled) ? 0.5 : 1)
            .accessibilityIdentifier("subscription.purchase")
            if let product = selectedProduct {
                Text(product.checkoutPriceDetail.map { "\(product.checkoutDisplayPrice) · \($0)" } ?? product.checkoutDisplayPrice)
                    .font(.footnote).foregroundStyle(Color.dsPaperInkSecondary)
                    .multilineTextAlignment(.center)
            }
            if usesPreviewPrices {
                Text("界面预览 · 示例价格，不可购买").font(.caption).foregroundStyle(Color.dsPaperInkSecondary)
            }
            Text("通过 Apple 账户付款，自动续费，可随时在 App Store 管理或取消。")
                .font(.caption).foregroundStyle(Color.dsPaperInkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(paperTone.opacity(reduceTransparency ? 1 : 0.84))
        .overlay(alignment: .top) { Divider() }
    }

    private func manageSubscription() {
        openURL(URL(string: "https://apps.apple.com/account/subscriptions")!) { accepted in
            if !accepted { managementError = "请打开系统设置，进入 Apple 账户 → 订阅。" }
        }
    }
}
