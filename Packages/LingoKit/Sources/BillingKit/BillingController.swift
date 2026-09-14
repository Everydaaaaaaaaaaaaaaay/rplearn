import BackendKit
import Foundation
import Observation
import PersistenceKit
import StoreKit

@MainActor
@Observable
public final class BillingController {
    private struct PendingCommand: Codable {
        let createdAt: Date
        let id: UUID
    }

    public enum CatalogState: Equatable {
        case notLoaded, loading, available, empty, failed, unavailable
    }
    public private(set) var catalogState: CatalogState = .notLoaded
    public var catalogStatusMessage: String {
        switch catalogState {
        case .notLoaded: "订阅方案尚未加载。"
        case .loading: "正在加载订阅方案…"
        case .available: ""
        case .empty: "App Store 尚未提供这些商品，当前暂不可购买。"
        case .unavailable: "购买服务尚未开通，当前无法付款。"
        case .failed: "订阅方案加载未完成，请重新加载。"
        }
    }

    public private(set) var entitlements: [BillingEntitlement] = []
    public private(set) var featureFlags: [String: BillingFeatureValue] = [:]
    public private(set) var lastError: String?
    public private(set) var message: String?
    public private(set) var operation: BillingOperationState = .idle
    public private(set) var products: [PurchasableProduct] = []
    public private(set) var tier: SubscriptionTier = .free

    public var offeredProducts: [PurchasableProduct] {
        products.filter { $0.coinAmount == 0 && $0.productID.hasSuffix(".monthly") }
    }
    public var coinProducts: [PurchasableProduct] { products.filter { $0.coinAmount > 0 } }
    public private(set) var purchasesEnabled = false
    private let refreshAssets: @Sendable () async throws -> Void

    private let backend: BackendClient
    private let defaults: UserDefaults
    private let economyStore: EconomyStore
    private let storefront: any StorefrontClient
    private let pendingKey = "billing.apple.pending-commands.v1"
    private var activeUserID: UUID?
    private var catalogByProductID: [String: BillingCatalogProduct] = [:]
    private var updatesTask: Task<Void, Never>?

    public init(
        backend: BackendClient,
        economyStore: EconomyStore,
        storefront: any StorefrontClient = StoreKitStorefront(),
        defaults: UserDefaults = .standard,
        refreshAssets: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.refreshAssets = refreshAssets
        self.backend = backend
        self.economyStore = economyStore
        self.storefront = storefront
        self.defaults = defaults
    }

    public func activate(identity: AuthIdentity, refreshImmediately: Bool = true) async {
        updatesTask?.cancel()
        activeUserID = identity.userID
        lastError = nil
        message = nil
        prunePendingCommands()
        startTransactionListener()
        if let profile = try? await economyStore.profile() {
            tier = profile.subscriptionTier
        }
        if refreshImmediately { await synchronize(showLoading: true) }
    }

    public func deactivate() {
        updatesTask?.cancel()
        updatesTask = nil
        activeUserID = nil
        products = []
        catalogState = .notLoaded
        purchasesEnabled = false
        entitlements = []
        featureFlags = [:]
        tier = .free
        operation = .idle
        lastError = nil
        message = nil
    }

    public func synchronize(showLoading: Bool = false) async {
        guard activeUserID != nil, operation == .idle else { return }
        operation = .loading
        catalogState = .loading
        do {
            try await refreshCatalogAndEntitlements()
            try await reconcileCurrentTransactions()
            try await refreshEntitlements()
            lastError = nil
        } catch {
            if catalogState == .loading { catalogState = .failed }
            let nsError = error as NSError
            let storeCancelled: Bool
            if case StoreKitError.userCancelled = error { storeCancelled = true } else { storeCancelled = false }
            if error is CancellationError || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
                || storeCancelled {
                lastError = nil
            } else {
                lastError = "订阅同步失败，请检查网络后重试。"
            }
        }
        operation = .idle
    }

    public func purchase(_ product: PurchasableProduct) async {
        guard operation == .idle, purchasesEnabled, let activeUserID,
              catalogByProductID[product.productID] != nil
        else {
            lastError = "订阅商品目录尚未准备好。"
            return
        }
        operation = .purchasing(product.productID)
        message = nil
        lastError = nil
        do {
            switch try await storefront.purchase(
                productID: product.productID,
                appAccountToken: activeUserID
            ) {
            case .cancelled:
                break
            case .pending:
                message = "购买正在等待 Apple 确认，确认后会自动生效。"
            case .purchased(let transaction):
                try await submitAndFinish(transaction)
                message = product.coinAmount > 0 ? "金币已到账。" : "订阅已生效，权益已同步。"
            }
        } catch {
            lastError = error.localizedDescription
        }
        operation = .idle
    }

    public func restorePurchases() async {
        guard activeUserID != nil else { return }
        operation = .restoring
        message = nil
        lastError = nil
        do {
            try await storefront.synchronize()
            try await reconcileCurrentTransactions()
            try await refreshEntitlements()
            message = tier == .free ? "没有找到可恢复的有效订阅。" : "购买记录已恢复。"
        } catch {
            lastError = error.localizedDescription
        }
        operation = .idle
    }

    public var currentValidityDescription: String? {
        let values = entitlements.compactMap(\.validUntil).sorted()
        guard let latest = values.last else { return nil }
        return "有效期至 \(Self.displayDate(latest) ?? latest)"
    }

    private func refreshCatalogAndEntitlements() async throws {
        async let catalogRequest = backend.billingCatalog()
        async let entitlementRequest = backend.billingEntitlements()
        let (catalog, snapshot) = try await (catalogRequest, entitlementRequest)
        purchasesEnabled = catalog.applePurchasesEnabled ?? true
        let appleCatalog = catalog.products.filter { $0.provider == "apple" }
        catalogByProductID = Dictionary(
            uniqueKeysWithValues: appleCatalog.map { ($0.productId, $0) }
        )
        // 权益展示不依赖 App Store 商品目录是否暂时可达。
        try await apply(snapshot)
        let metadata = try await storefront.loadProducts(
            ids: Set(catalogByProductID.keys)
        )
        products = metadata.compactMap { item in
            guard let catalog = catalogByProductID[item.productID] else {
                return nil
            }
            return PurchasableProduct(
                coinAmount: catalog.coinAmount ?? 0,
                ticketCount: catalog.ticketCount ?? 0,
                displayName: item.displayName,
                displayPrice: item.displayPrice,
                introductoryOffer: item.introductoryOffer,
                periodDescription: item.periodDescription,
                productDescription: item.productDescription,
                productID: item.productID,
                tier: catalog.tier
            )
        }
        .sorted(by: Self.productOrder)
        catalogState = !purchasesEnabled ? .unavailable : products.isEmpty ? .empty : .available
    }

    private func refreshEntitlements() async throws {
        try await apply(backend.billingEntitlements())
    }

    private func apply(_ snapshot: BillingEntitlementSnapshot) async throws {
        tier = snapshot.tier
        featureFlags = snapshot.featureFlags
        entitlements = snapshot.entitlements
        try await economyStore.applyAuthoritativeEntitlement(
            tier: snapshot.tier,
            friendSlotLimit: snapshot.featureFlags["friendSlotLimit"]?.integerValue
        )
    }

    private func reconcileCurrentTransactions() async throws {
        guard let activeUserID else { return }
        for transaction in try await storefront.currentTransactions()
        where catalogByProductID[transaction.productID] != nil {
            if let token = transaction.appAccountToken, token != activeUserID {
                continue
            }
            try await submitAndFinish(transaction)
        }
    }

    private func submitAndFinish(_ transaction: StorefrontTransaction) async throws {
        guard activeUserID != nil,
              catalogByProductID[transaction.productID] != nil
        else {
            return
        }
        let intent = String(transaction.transactionID)
        let commandID = pendingCommandID(for: intent)
        let snapshot = try await backend.submitAppleTransaction(
            transaction.signedTransaction,
            idempotencyKey: commandID
        )
        try await apply(snapshot)
        try await refreshAssets()
        await storefront.finish(transactionID: transaction.transactionID)
        completeCommand(for: intent)
    }

    private func startTransactionListener() {
        let storefront = self.storefront
        updatesTask = Task { [weak self] in
            let updates = await storefront.transactionUpdates()
            for await update in updates {
                guard !Task.isCancelled, let self else { return }
                switch update {
                case .transaction(let transaction):
                    do {
                        try await self.submitAndFinish(transaction)
                        self.lastError = nil
                    } catch {
                        self.lastError = error.localizedDescription
                    }
                case .verificationFailed:
                    self.lastError = StoreKitStorefrontError.verificationFailed.localizedDescription
                }
            }
        }
    }

    private func commandKey(for transactionID: String) -> String {
        "\(activeUserID?.uuidString.lowercased() ?? "signed-out")|\(transactionID)"
    }

    private func pendingCommandID(for transactionID: String) -> UUID {
        var commands = pendingCommands()
        let key = commandKey(for: transactionID)
        if let pending = commands[key] {
            return pending.id
        }
        let pending = PendingCommand(createdAt: .now, id: UUID())
        commands[key] = pending
        savePendingCommands(commands)
        return pending.id
    }

    private func completeCommand(for transactionID: String) {
        var commands = pendingCommands()
        commands.removeValue(forKey: commandKey(for: transactionID))
        savePendingCommands(commands)
    }

    private func pendingCommands() -> [String: PendingCommand] {
        guard let data = defaults.data(forKey: pendingKey) else { return [:] }
        return (try? JSONDecoder().decode([String: PendingCommand].self, from: data)) ?? [:]
    }

    private func savePendingCommands(_ commands: [String: PendingCommand]) {
        if commands.isEmpty {
            defaults.removeObject(forKey: pendingKey)
        } else if let data = try? JSONEncoder().encode(commands) {
            defaults.set(data, forKey: pendingKey)
        }
    }

    private func prunePendingCommands() {
        let cutoff = Date.now.addingTimeInterval(-90 * 24 * 60 * 60)
        savePendingCommands(
            pendingCommands().filter { $0.value.createdAt >= cutoff }
        )
    }

    private static func productOrder(
        _ left: PurchasableProduct,
        _ right: PurchasableProduct
    ) -> Bool {
        let tierRank: [SubscriptionTier: Int] = [.free: 0, .plus: 1, .pro: 2]
        let leftRank = tierRank[left.tier] ?? 0
        let rightRank = tierRank[right.tier] ?? 0
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return left.productID.localizedStandardCompare(right.productID) == .orderedAscending
    }

    private static func displayDate(_ value: String) -> String? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
