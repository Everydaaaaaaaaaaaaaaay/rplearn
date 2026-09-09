import Foundation

public enum StorefrontOfferPaymentMode: Sendable, Equatable {
    case freeTrial
    case payAsYouGo
    case payUpFront
}

public struct StorefrontIntroductoryOffer: Sendable, Equatable {
    public let displayPrice: String
    public let paymentMode: StorefrontOfferPaymentMode
    public let periodDescription: String

    public init(
        displayPrice: String,
        paymentMode: StorefrontOfferPaymentMode,
        periodDescription: String
    ) {
        self.displayPrice = displayPrice
        self.paymentMode = paymentMode
        self.periodDescription = periodDescription
    }
}

public struct StoreProductMetadata: Sendable, Equatable {
    public let displayName: String
    public let displayPrice: String
    public let introductoryOffer: StorefrontIntroductoryOffer?
    public let periodDescription: String?
    public let productDescription: String
    public let productID: String

    public init(
        displayName: String,
        displayPrice: String,
        introductoryOffer: StorefrontIntroductoryOffer? = nil,
        periodDescription: String?,
        productDescription: String,
        productID: String
    ) {
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.introductoryOffer = introductoryOffer
        self.periodDescription = periodDescription
        self.productDescription = productDescription
        self.productID = productID
    }
}

public struct StorefrontTransaction: Sendable, Equatable {
    public let appAccountToken: UUID?
    public let productID: String
    public let signedTransaction: String
    public let transactionID: UInt64

    public init(
        appAccountToken: UUID?,
        productID: String,
        signedTransaction: String,
        transactionID: UInt64
    ) {
        self.appAccountToken = appAccountToken
        self.productID = productID
        self.signedTransaction = signedTransaction
        self.transactionID = transactionID
    }
}

public enum StorefrontPurchaseResult: Sendable, Equatable {
    case cancelled
    case pending
    case purchased(StorefrontTransaction)
}

public enum StorefrontTransactionUpdate: Sendable, Equatable {
    case transaction(StorefrontTransaction)
    case verificationFailed
}

public protocol StorefrontClient: Sendable {
    func currentTransactions() async throws -> [StorefrontTransaction]
    func finish(transactionID: UInt64) async
    func loadProducts(ids: Set<String>) async throws -> [StoreProductMetadata]
    func purchase(
        productID: String,
        appAccountToken: UUID
    ) async throws -> StorefrontPurchaseResult
    func synchronize() async throws
    func transactionUpdates() async -> AsyncStream<StorefrontTransactionUpdate>
}
