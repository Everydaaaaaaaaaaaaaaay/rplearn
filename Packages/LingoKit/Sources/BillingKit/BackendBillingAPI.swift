import BackendKit
import Foundation

private struct SignedTransactionBody: Encodable, Sendable {
    let signedTransaction: String
}

extension BackendClient {
    func billingCatalog() async throws -> BillingProductsResponse {
        try await get("/v1/billing/products")
    }

    public func billingProducts() async throws -> [BillingCatalogProduct] {
        let response: BillingProductsResponse = try await get("/v1/billing/products")
        return response.products
    }

    public func billingEntitlements() async throws -> BillingEntitlementSnapshot {
        try await get("/v1/billing/entitlements")
    }

    public func submitAppleTransaction(
        _ signedTransaction: String,
        idempotencyKey: UUID
    ) async throws -> BillingEntitlementSnapshot {
        try await send(
            path: "/v1/billing/apple/transactions",
            method: "POST",
            body: SignedTransactionBody(signedTransaction: signedTransaction),
            idempotencyKey: idempotencyKey
        )
    }
}

