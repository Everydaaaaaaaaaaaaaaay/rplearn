import Foundation
import StoreKit

public enum StoreKitStorefrontError: LocalizedError, Sendable {
    case productUnavailable
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .productUnavailable:
            "这个订阅商品当前不可购买，请稍后重试。"
        case .verificationFailed:
            "Apple 交易签名未通过设备校验。"
        }
    }
}

public actor StoreKitStorefront: StorefrontClient {
    private var products: [String: Product] = [:]
    private var transactions: [UInt64: Transaction] = [:]

    public init() {}

    public func loadProducts(ids: Set<String>) async throws -> [StoreProductMetadata] {
        let loaded = try await Product.products(for: ids)
        products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        var metadata: [StoreProductMetadata] = []
        metadata.reserveCapacity(loaded.count)
        for product in loaded {
            metadata.append(
                StoreProductMetadata(
                    displayName: product.displayName,
                    displayPrice: product.displayPrice,
                    introductoryOffer: await Self.eligibleIntroductoryOffer(for: product),
                    periodDescription: Self.periodDescription(product.subscription?.subscriptionPeriod),
                    productDescription: product.description,
                    productID: product.id
                )
            )
        }
        return metadata
    }

    public func purchase(
        productID: String,
        appAccountToken: UUID
    ) async throws -> StorefrontPurchaseResult {
        guard let product = products[productID] else {
            throw StoreKitStorefrontError.productUnavailable
        }
        switch try await product.purchase(options: [.appAccountToken(appAccountToken)]) {
        case .success(let verification):
            let transaction = try verifiedTransaction(verification)
            transactions[transaction.id] = transaction
            return .purchased(Self.envelope(transaction, jws: verification.jwsRepresentation))
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .pending
        }
    }

    public func currentTransactions() async throws -> [StorefrontTransaction] {
        var values: [StorefrontTransaction] = []
        for await verification in Transaction.currentEntitlements {
            let transaction = try verifiedTransaction(verification)
            transactions[transaction.id] = transaction
            values.append(Self.envelope(transaction, jws: verification.jwsRepresentation))
        }
        return values
    }

    public func finish(transactionID: UInt64) async {
        if let transaction = transactions.removeValue(forKey: transactionID) {
            await transaction.finish()
            return
        }
        for await verification in Transaction.unfinished {
            guard case .verified(let transaction) = verification,
                  transaction.id == transactionID
            else {
                continue
            }
            await transaction.finish()
            return
        }
    }

    public func synchronize() async throws {
        try await AppStore.sync()
    }

    public func transactionUpdates() async -> AsyncStream<StorefrontTransactionUpdate> {
        AsyncStream { continuation in
            let task = Task {
                for await verification in Transaction.updates {
                    switch verification {
                    case .verified(let transaction):
                        transactions[transaction.id] = transaction
                        continuation.yield(
                            .transaction(
                                Self.envelope(
                                    transaction,
                                    jws: verification.jwsRepresentation
                                )
                            )
                        )
                    case .unverified:
                        continuation.yield(.verificationFailed)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func verifiedTransaction(
        _ result: VerificationResult<Transaction>
    ) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            transaction
        case .unverified:
            throw StoreKitStorefrontError.verificationFailed
        }
    }

    private static func envelope(
        _ transaction: Transaction,
        jws: String
    ) -> StorefrontTransaction {
        StorefrontTransaction(
            appAccountToken: transaction.appAccountToken,
            productID: transaction.productID,
            signedTransaction: jws,
            transactionID: transaction.id
        )
    }

    private static func periodDescription(
        _ period: Product.SubscriptionPeriod?
    ) -> String? {
        guard let period else { return nil }
        let unit = switch period.unit {
        case .day: "天"
        case .week: "周"
        case .month: "个月"
        case .year: "年"
        @unknown default: "期"
        }
        return period.value == 1 ? "每\(unit)" : "每 \(period.value) \(unit)"
    }

    private static func eligibleIntroductoryOffer(
        for product: Product
    ) async -> StorefrontIntroductoryOffer? {
        guard let subscription = product.subscription,
              let offer = subscription.introductoryOffer,
              await subscription.isEligibleForIntroOffer
        else {
            return nil
        }

        let paymentMode: StorefrontOfferPaymentMode
        if offer.paymentMode == .freeTrial {
            paymentMode = .freeTrial
        } else if offer.paymentMode == .payUpFront {
            paymentMode = .payUpFront
        } else {
            paymentMode = .payAsYouGo
        }
        return StorefrontIntroductoryOffer(
            displayPrice: offer.displayPrice,
            paymentMode: paymentMode,
            periodDescription: introductoryPeriodDescription(
                period: offer.period,
                periodCount: offer.periodCount
            )
        )
    }

    private static func introductoryPeriodDescription(
        period: Product.SubscriptionPeriod,
        periodCount: Int
    ) -> String {
        let count = period.value * periodCount
        switch period.unit {
        case .day:
            return count == 1 ? "首日" : "前 \(count) 天"
        case .week:
            return count == 1 ? "首周" : "前 \(count) 周"
        case .month:
            return count == 1 ? "首月" : "前 \(count) 个月"
        case .year:
            return count == 1 ? "首年" : "前 \(count) 年"
        @unknown default:
            return "首个优惠期"
        }
    }
}
