import { describe, expect, it } from "vitest";
import { entitlementStatusForApple } from "../../../src/modules/billing/service.js";
import type { VerifiedStoreTransaction } from "../../../src/modules/billing/types.js";

function transaction(
  overrides: Partial<VerifiedStoreTransaction> = {},
): VerifiedStoreTransaction {
  return {
    environment: "sandbox",
    expiresAt: new Date("2030-02-01T00:00:00.000Z"),
    originalTransactionId: "original-1",
    productId: "com.tiantian.lingotrip.plus.monthly",
    purchasedAt: new Date("2030-01-01T00:00:00.000Z"),
    rawPayload: {},
    signedAt: new Date("2030-01-01T00:00:00.000Z"),
    transactionId: "transaction-1",
    ...overrides,
  };
}

describe("Apple entitlement status", () => {
  const now = new Date("2030-01-15T00:00:00.000Z");

  it("prioritizes revocation and provider lifecycle status", () => {
    expect(
      entitlementStatusForApple(
        transaction({ revokedAt: new Date("2030-01-10T00:00:00.000Z") }),
        undefined,
        1,
        now,
      ),
    ).toBe("revoked");
    expect(entitlementStatusForApple(transaction(), undefined, 4, now)).toBe("grace");
    expect(entitlementStatusForApple(transaction(), undefined, 3, now)).toBe(
      "billing_retry",
    );
  });

  it("falls back to verified expiration and grace dates", () => {
    expect(entitlementStatusForApple(transaction(), undefined, undefined, now)).toBe(
      "active",
    );
    expect(
      entitlementStatusForApple(
        transaction({ expiresAt: new Date("2030-01-10T00:00:00.000Z") }),
        {
          gracePeriodExpiresAt: new Date("2030-01-20T00:00:00.000Z"),
          rawPayload: {},
        },
        undefined,
        now,
      ),
    ).toBe("grace");
  });
});
