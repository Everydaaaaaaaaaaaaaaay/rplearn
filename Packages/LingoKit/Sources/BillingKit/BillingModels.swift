import Foundation
import PersistenceKit

public enum BillingFeatureValue: Codable, Sendable, Equatable {
    case boolean(Bool)
    case number(Double)
    case string(String)

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let boolean = try? value.decode(Bool.self) {
            self = .boolean(boolean)
        } else if let number = try? value.decode(Double.self) {
            self = .number(number)
        } else {
            self = .string(try value.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .boolean(let boolean):
            try value.encode(boolean)
        case .number(let number):
            try value.encode(number)
        case .string(let string):
            try value.encode(string)
        }
    }

    public var integerValue: Int? {
        guard case .number(let value) = self,
              value.isFinite,
              value.rounded() == value,
              value >= Double(Int.min),
              value <= Double(Int.max)
        else {
            return nil
        }
        return Int(value)
    }
}

public struct BillingCatalogProduct: Decodable, Sendable, Equatable {
    public let featureFlags: [String: BillingFeatureValue]
    public let planId: String
    public let productId: String
    public let provider: String
    public let tier: SubscriptionTier
}

struct BillingProductsResponse: Decodable, Sendable {
    let products: [BillingCatalogProduct]
}

public struct BillingEntitlement: Decodable, Sendable, Equatable {
    public let entitlementKey: String
    public let provider: String
    public let status: String
    public let validUntil: String?
}

public struct BillingEntitlementSnapshot: Decodable, Sendable, Equatable {
    public let entitlements: [BillingEntitlement]
    public let featureFlags: [String: BillingFeatureValue]
    public let tier: SubscriptionTier
}

public struct PurchasableProduct: Identifiable, Sendable, Equatable {
    public var id: String { productID }

    public let displayName: String
    public let displayPrice: String
    public let periodDescription: String?
    public let productDescription: String
    public let productID: String
    public let tier: SubscriptionTier

    public init(
        displayName: String,
        displayPrice: String,
        periodDescription: String?,
        productDescription: String,
        productID: String,
        tier: SubscriptionTier
    ) {
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.periodDescription = periodDescription
        self.productDescription = productDescription
        self.productID = productID
        self.tier = tier
    }
}

public enum BillingOperationState: Sendable, Equatable {
    case idle
    case loading
    case purchasing(String)
    case restoring
}

