import type { StatusResponse } from "@apple/app-store-server-library";
import { describe, expect, it, vi } from "vitest";
import { loadConfig } from "../../../src/config/env.js";
import type { AppError } from "../../../src/shared/errors.js";
import { createAppleBillingStatusClient } from "../../../src/modules/billing/apple/server-api-client.js";
import type { AppleBillingVerifier } from "../../../src/modules/billing/apple/verifier.js";

const originalTransactionId = "original-transaction";

function config() {
  return loadConfig({
    APPLE_BILLING_APP_APPLE_ID: "123456789",
    APPLE_BILLING_BUNDLE_ID: "com.example.app",
    APPLE_BILLING_ENABLED: "true",
    APPLE_BILLING_ISSUER_ID: "019c0123-4567-789a-8bcd-ef0123456789",
    APPLE_BILLING_KEY_ID: "TESTKEY123",
    APPLE_BILLING_PRIVATE_KEY_BASE64: Buffer.from(
      "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----",
    ).toString("base64"),
    APPLE_BILLING_ROOT_CA_CERTIFICATES_BASE64:
      Buffer.from("certificate").toString("base64"),
  });
}

function verifier(
  environment: "production" | "sandbox" = "sandbox",
): AppleBillingVerifier {
  return {
    verifyNotification: vi.fn(),
    verifyRenewal: vi.fn().mockResolvedValue({
      autoRenewEnabled: true,
      rawPayload: {},
    }),
    verifyTransaction: vi.fn().mockResolvedValue({
      environment,
      expiresAt: new Date("2030-02-01T00:00:00.000Z"),
      originalTransactionId,
      productId: "com.example.app.plus.monthly",
      purchasedAt: new Date("2030-01-01T00:00:00.000Z"),
      rawPayload: {},
      signedAt: new Date("2030-01-01T00:00:00.000Z"),
      transactionId: "transaction-1",
    }),
  };
}

function response(): StatusResponse {
  return {
    bundleId: "com.example.app",
    data: [
      {
        lastTransactions: [
          {
            originalTransactionId,
            signedRenewalInfo: "signed-renewal",
            signedTransactionInfo: "signed-transaction",
            status: 1,
          },
        ],
      },
    ],
    environment: "Sandbox",
  };
}

describe("AppleBillingStatusClient", () => {
  it("verifies every signed status payload before exposing it", async () => {
    const billingVerifier = verifier();
    const getAllSubscriptionStatuses = vi.fn().mockResolvedValue(response());
    const client = createAppleBillingStatusClient(config(), billingVerifier, () => ({
      getAllSubscriptionStatuses,
    }));

    const statuses = await client.statuses("sandbox", "transaction-1");

    expect(statuses).toHaveLength(1);
    expect(statuses[0]).toMatchObject({
      providerStatus: 1,
      renewal: { autoRenewEnabled: true },
      transaction: { originalTransactionId },
    });
    expect(billingVerifier.verifyTransaction).toHaveBeenCalledWith(
      "signed-transaction",
      "sandbox",
    );
    expect(billingVerifier.verifyRenewal).toHaveBeenCalledWith(
      "signed-renewal",
      "sandbox",
    );
  });

  it("rejects responses whose signed transaction has another environment", async () => {
    const client = createAppleBillingStatusClient(
      config(),
      verifier("production"),
      () => ({
        getAllSubscriptionStatuses: vi.fn().mockResolvedValue(response()),
      }),
    );

    await expect(client.statuses("sandbox", "transaction-1")).rejects.toMatchObject({
      code: "APPLE_SERVER_API_PROTOCOL_ERROR",
    } satisfies Partial<AppError>);
  });

  it("normalizes upstream failures without exposing provider details", async () => {
    const client = createAppleBillingStatusClient(config(), verifier(), () => ({
      getAllSubscriptionStatuses: vi
        .fn()
        .mockRejectedValue(new Error("sensitive provider response")),
    }));

    await expect(client.statuses("sandbox", "transaction-1")).rejects.toMatchObject({
      code: "APPLE_SERVER_API_UNAVAILABLE",
    } satisfies Partial<AppError>);
  });
});
