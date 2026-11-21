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
            VStack(alignment: .leading, spacing: Puff.Space.m) {
                introduction
                benefits
                plans
                if let error = billing.lastError {
                    Text(error)
                        .font(.puff(.footnote, Puff.Weight.label))
                        .foregroundStyle(Puff.Palette.cherry)
                        .accessibilityIdentifier("subscription.error")
                }
                if let message = billing.message {
                    Text(message)
                        .font(.puff(.footnote, Puff.Weight.label))
                        .foregroundStyle(Puff.Palette.inkSoft)
                }
                HStack(spacing: Puff.Space.l) {
                    Button("恢复购买") { Task { await billing.restorePurchases() } }
                        .disabled(busy)
                        .accessibilityIdentifier("subscription.restore")
                    Button("管理订阅", action: manageSubscription)
                }
                .font(.puff(.footnote, Puff.Weight.emphasis))
                .foregroundStyle(PuffCandy.sky.deep)
                .buttonStyle(.puffSquish)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, Puff.Space.m)
            .padding(.top, Puff.Space.xs)
            .padding(.bottom, Puff.Space.m)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("subscription.content")
        .foregroundStyle(Puff.Palette.ink)
        .tint(PuffCandy.sunny.deep)
        .safeAreaInset(edge: .bottom, spacing: 0) { purchaseDock }
        .background(Puff.Palette.page.ignoresSafeArea())
        .task { await billing.synchronize(showLoading: true) }
        .alert("无法打开订阅管理", isPresented: Binding(
            get: { managementError != nil }, set: { if !$0 { managementError = nil } }
        )) { Button("好", role: .cancel) {} } message: { Text(managementError ?? "") }
    }

    private var introduction: some View {
        HStack(spacing: Puff.Space.m) {
            PuffIconBubble("crown.fill", candy: .sunny, size: 60)
            VStack(alignment: .leading, spacing: 6) {
                Text("咕游记会员")
                    .font(.puff(.title2, Puff.Weight.display))
                    .foregroundStyle(Puff.Palette.ink)
                if billing.tier != .free {
                    PuffTag("当前：\(billing.tier.displayName)", systemImage: "checkmark.seal.fill", candy: .sunny)
                    if let validity = billing.currentValidityDescription {
                        Text(validity)
                            .font(.puff(.footnote, Puff.Weight.label))
                            .foregroundStyle(Puff.Palette.inkSoft)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Puff.Space.m)
        .puffCard(radius: Puff.Radius.huge, face: PuffCandy.sunny.wash, border: PuffCandy.sunny.base.opacity(0.35), lip: PuffCandy.sunny.base.opacity(0.4))
    }

    private var benefits: some View {
        HStack(alignment: .top, spacing: Puff.Space.xs) {
            benefit("person.2.fill", "更多旅途朋友", .sky)
            benefit("text.bubble.fill", "更连贯的对话", .mint)
            benefit("heart.fill", "更长久的记忆", .bubblegum)
        }
    }

    private func benefit(_ symbol: String, _ title: String, _ candy: PuffCandy) -> some View {
        VStack(spacing: 8) {
            PuffIconBubble(symbol, candy: candy, size: 44)
            Text(title)
                .font(.puff(.caption, Puff.Weight.emphasis))
                .foregroundStyle(Puff.Palette.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Puff.Space.s)
        .puffCard(radius: Puff.Radius.large)
        .accessibilityElement(children: .combine)
    }

    private var plans: some View {
        VStack(alignment: .leading, spacing: Puff.Space.s) {
            Text("选择会员方案")
                .font(.puff(.headline, Puff.Weight.title))
                .foregroundStyle(Puff.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if products.isEmpty {
                if billing.operation == .loading {
                    HStack(spacing: 10) {
                        PuffLoadingDots().scaleEffect(0.7).frame(width: 46, height: 20)
                        Text("正在获取 App Store 价格")
                    }
                    .font(.puff(.subheadline, Puff.Weight.label))
                    .foregroundStyle(Puff.Palette.inkSoft)
                } else {
                    Text(billing.catalogState == .available
                        ? "App Store 尚未提供会员订阅方案，请稍后重新加载。"
                        : billing.catalogStatusMessage)
                        .font(.puff(.subheadline, Puff.Weight.label))
                        .foregroundStyle(Puff.Palette.inkSoft)
                        .accessibilityIdentifier("subscription.catalogStatus")
                    if billing.catalogState != .unavailable {
                        Button("重新加载") { Task { await billing.synchronize(showLoading: true) } }
                            .buttonStyle(PuffCandyButtonStyle(.sky))
                            .accessibilityIdentifier("subscription.reload")
                    }
                }
            } else {
                ForEach(products) { product in
                    plan(product)
                }
            }
        }
    }

    private func plan(_ product: PurchasableProduct) -> some View {
        let isSelected = selectedProduct?.id == product.id
        let candy: PuffCandy = product.tier == .pro ? .grape : .sunny
        return Button {
            Haptics.selection()
            selectedProductID = product.id
        } label: {
            HStack(alignment: .center, spacing: Puff.Space.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: Puff.Weight.icon))
                    .foregroundStyle(isSelected ? candy.base : Puff.Palette.inkFaint)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(product.tier.displayName)
                            .font(.puff(.title3, Puff.Weight.title))
                            .foregroundStyle(Puff.Palette.ink)
                        Spacer(minLength: 8)
                        Text(product.checkoutDisplayPrice)
                            .font(.puff(.headline, Puff.Weight.title))
                            .monospacedDigit()
                            .foregroundStyle(candy.deep)
                    }
                    if product.ticketCount > 0 {
                        PuffTag("每期 \(product.ticketCount) 张通用机票", systemImage: "ticket.fill", candy: candy)
                    }
                    if let detail = product.checkoutPriceDetail {
                        Text(detail)
                            .font(.puff(.footnote, Puff.Weight.label))
                            .foregroundStyle(Puff.Palette.inkSoft)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Puff.Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(PuffCardButtonStyle(
            radius: Puff.Radius.large,
            face: isSelected ? candy.wash : Puff.Palette.card,
            border: isSelected ? candy.base : Puff.Palette.line,
            lip: isSelected ? candy.lip.opacity(0.6) : Puff.Palette.lip
        ))
        .animation(Puff.Motion.pop, value: isSelected)
        .disabled(busy)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("subscription.plan.\(product.tier.rawValue)")
    }

    private var purchaseDock: some View {
        VStack(spacing: Puff.Space.xs) {
            Button {
                if isCurrentPlan {
                    manageSubscription()
                } else if let selectedProduct, !usesPreviewPrices {
                    Task { await billing.purchase(selectedProduct) }
                }
            } label: {
                HStack(spacing: 10) {
                    if busy { PuffLoadingDots().scaleEffect(0.6).frame(width: 40, height: 20) }
                    Text(isCurrentPlan ? "管理当前订阅" : selectedProduct.map { "订阅 \($0.tier.displayName)" } ?? "订阅会员")
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(PuffCandyButtonStyle(.sunny))
            .disabled(usesPreviewPrices || busy || selectedProduct == nil || (!isCurrentPlan && !billing.purchasesEnabled))
            .accessibilityIdentifier("subscription.purchase")
            if let product = selectedProduct {
                Text(product.checkoutPriceDetail.map { "\(product.checkoutDisplayPrice) · \($0)" } ?? product.checkoutDisplayPrice)
                    .font(.puff(.footnote, Puff.Weight.label))
                    .foregroundStyle(Puff.Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
            if usesPreviewPrices {
                Text("界面预览 · 示例价格，不可购买")
                    .font(.puff(.caption, Puff.Weight.label))
                    .foregroundStyle(Puff.Palette.inkSoft)
            }
            // App Store 要求展示自动续费条款。
            Text("通过 Apple 账户付款，自动续费，可随时在 App Store 管理或取消。")
                .font(.puff(.caption, Puff.Weight.body))
                .foregroundStyle(Puff.Palette.inkFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, Puff.Space.l)
        .padding(.vertical, Puff.Space.m)
        .frame(maxWidth: .infinity)
        .background(Puff.Palette.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Puff.Palette.line).frame(height: 1) }
    }

    private func manageSubscription() {
        openURL(URL(string: "https://apps.apple.com/account/subscriptions")!) { accepted in
            if !accepted { managementError = "请打开系统设置，进入 Apple 账户 → 订阅。" }
        }
    }
}
