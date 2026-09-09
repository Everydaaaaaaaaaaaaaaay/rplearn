import BackendKit
import Foundation
import PersistenceKit
import Testing
@testable import BillingKit

@Suite("BillingController")
struct BillingControllerTests {
    private final class MemoryCredentials: AuthCredentialStore, @unchecked Sendable {
        private let credential: StoredAuthCredential

        init(userID: UUID) {
            credential = StoredAuthCredential(
                refreshToken: "refresh",
                refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_893_456_000),
                sessionID: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456789")!,
                userID: userID
            )
        }

        func load() throws -> StoredAuthCredential? { credential }
        func remove() throws {}
        func save(_ credential: StoredAuthCredential) throws {}
    }

    private actor BillingTransport: BackendTransport {
        private var subscribed = false
        private(set) var submittedIdempotencyKeys: [String] = []

        func data(for request: URLRequest) async throws -> BackendTransportResponse {
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/auth/refresh"):
                return json(
                    """
                    {
                      "accessToken":"access",
                      "accessTokenExpiresIn":900,
                      "refreshToken":"rotated",
                      "refreshTokenExpiresAt":"2030-01-01T00:00:00.000Z",
                      "sessionId":"019c0123-4567-789a-8bcd-ef0123456789",
                      "tokenType":"Bearer",
                      "userId":"019c0123-4567-789a-8bcd-ef0123456790"
                    }
                    """
                )
            case ("GET", "/v1/billing/products"):
                return json(
                    """
                    {
                      "products":[
                        {
                          "featureFlags":{"friendSlotLimit":10},
                          "planId":"plus",
                          "productId":"com.tiantian.lingotrip.plus.monthly",
                          "provider":"apple",
                          "tier":"plus"
                        },
                        {
                          "featureFlags":{"friendSlotLimit":10},
                          "planId":"plus",
                          "productId":"com.tiantian.lingotrip.plus.yearly",
                          "provider":"apple",
                          "tier":"plus"
                        },
                        {
                          "featureFlags":{"friendSlotLimit":30},
                          "planId":"pro",
                          "productId":"com.tiantian.lingotrip.pro.monthly",
                          "provider":"apple",
                          "tier":"pro"
                        }
                      ]
                    }
                    """
                )
            case ("GET", "/v1/billing/entitlements"):
                return json(entitlementsJSON())
            case ("POST", "/v1/billing/apple/transactions"):
                submittedIdempotencyKeys.append(
                    request.value(forHTTPHeaderField: "idempotency-key") ?? ""
                )
                subscribed = true
                return json(entitlementsJSON())
            default:
                return json(
                    #"{"code":"NOT_FOUND","message":"not found","requestId":"request"}"#,
                    status: 404
                )
            }
        }

        private func entitlementsJSON() -> String {
            if subscribed {
                return """
                {
                  "entitlements":[{
                    "entitlementKey":"subscription",
                    "provider":"apple",
                    "status":"active",
                    "validUntil":"2030-01-01T00:00:00.000Z"
                  }],
                  "featureFlags":{"friendSlotLimit":30},
                  "tier":"pro"
                }
                """
            }
            return """
            {
              "entitlements":[],
              "featureFlags":{"friendSlotLimit":5},
              "tier":"free"
            }
            """
        }

        private func json(
            _ value: String,
            status: Int = 200
        ) -> BackendTransportResponse {
            BackendTransportResponse(
                data: Data(value.utf8),
                headers: [:],
                statusCode: status
            )
        }
    }

    private actor FakeStorefront: StorefrontClient {
        private let transactions: [StorefrontTransaction]
        private(set) var finished: [UInt64] = []

        init(transactions: [StorefrontTransaction]) {
            self.transactions = transactions
        }

        func currentTransactions() async throws -> [StorefrontTransaction] {
            transactions
        }

        func finish(transactionID: UInt64) async {
            finished.append(transactionID)
        }

        func loadProducts(ids: Set<String>) async throws -> [StoreProductMetadata] {
            ids.map {
                StoreProductMetadata(
                    displayName: "LingoTrip Pro",
                    displayPrice: "¥48.00",
                    introductoryOffer: $0.hasSuffix("plus.monthly")
                        ? StorefrontIntroductoryOffer(
                            displayPrice: "¥29.00",
                            paymentMode: .payAsYouGo,
                            periodDescription: "首月"
                        )
                        : nil,
                    periodDescription: "每个月",
                    productDescription: "Pro",
                    productID: $0
                )
            }
        }

        func purchase(
            productID: String,
            appAccountToken: UUID
        ) async throws -> StorefrontPurchaseResult {
            .cancelled
        }

        func synchronize() async throws {}

        func transactionUpdates() async -> AsyncStream<StorefrontTransactionUpdate> {
            AsyncStream { $0.finish() }
        }
    }

    @Test("遗留交易经服务端确认后才结束并投影权益")
    @MainActor
    func recoversVerifiedTransaction() async throws {
        let userID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
        let transaction = StorefrontTransaction(
            appAccountToken: userID,
            productID: "com.tiantian.lingotrip.pro.monthly",
            signedTransaction: "signed-transaction",
            transactionID: 42
        )
        let transport = BillingTransport()
        let storefront = FakeStorefront(transactions: [transaction])
        let fixture = try makeController(
            userID: userID,
            transport: transport,
            storefront: storefront
        )

        await fixture.controller.activate(
            identity: AuthIdentity(
                sessionID: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456789")!,
                userID: userID
            )
        )

        #expect(fixture.controller.tier == .pro)
        #expect(fixture.controller.products.count == 3)
        #expect(fixture.controller.offeredProducts.map(\.productID) == [
            "com.tiantian.lingotrip.plus.monthly",
        ])
        #expect(fixture.controller.offeredProducts.first?.checkoutDisplayPrice == "¥29.00")
        #expect(
            fixture.controller.offeredProducts.first?.checkoutPriceDetail
                == "首月优惠，之后 ¥48.00 · 每个月"
        )
        #expect(try await fixture.economy.profile().subscriptionTier == .pro)
        #expect(try await fixture.economy.profile().friendSlotLimit == 30)
        #expect(await storefront.finished == [42])
        let idempotencyKeys = await transport.submittedIdempotencyKeys
        #expect(idempotencyKeys.count == 1)
        #expect(UUID(uuidString: idempotencyKeys[0]) != nil)
    }

    @Test("其他账号的 appAccountToken 不会被提交或结束")
    @MainActor
    func rejectsCrossAccountTransaction() async throws {
        let userID = UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456790")!
        let transaction = StorefrontTransaction(
            appAccountToken: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456799")!,
            productID: "com.tiantian.lingotrip.pro.monthly",
            signedTransaction: "signed-for-another-user",
            transactionID: 99
        )
        let transport = BillingTransport()
        let storefront = FakeStorefront(transactions: [transaction])
        let fixture = try makeController(
            userID: userID,
            transport: transport,
            storefront: storefront
        )

        await fixture.controller.activate(
            identity: AuthIdentity(
                sessionID: UUID(uuidString: "019c0123-4567-789a-8bcd-ef0123456789")!,
                userID: userID
            )
        )

        #expect(fixture.controller.tier == .free)
        #expect(await transport.submittedIdempotencyKeys.isEmpty)
        #expect(await storefront.finished.isEmpty)
    }

    @MainActor
    private func makeController(
        userID: UUID,
        transport: BillingTransport,
        storefront: FakeStorefront
    ) throws -> (controller: BillingController, economy: EconomyStore) {
        let backend = BackendClient(
            configuration: BackendConfiguration(
                baseURL: URL(string: "https://api.example.com")!
            ),
            credentialStore: MemoryCredentials(userID: userID),
            transport: transport
        )
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let economy = EconomyStore(modelContainer: container)
        let suite = try #require(
            UserDefaults(suiteName: "BillingControllerTests.\(UUID().uuidString)")
        )
        return (
            BillingController(
                backend: backend,
                economyStore: economy,
                storefront: storefront,
                defaults: suite
            ),
            economy
        )
    }
}
