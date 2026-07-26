import pino from "pino";
import { describe, expect, it } from "vitest";
import { createLoggerOptions } from "../../src/app/logger.js";

describe("logger redaction", () => {
  it("redacts credentials in common structured fields", () => {
    const lines: string[] = [];
    const destination = {
      write(chunk: string): void {
        lines.push(chunk);
      },
    };
    const logger = pino(createLoggerOptions("info"), destination);

    logger.info(
      {
        apiKey: "api-key-value",
        adminApiKeys: [
          {
            keyId: "primary",
            token: "admin-api-token-value",
          },
        ],
        appleBillingPrivateKeyBase64: "apple-billing-private-key-value",
        authTokenHashPepper: "pepper-value",
        authorizationCode: "authorization-code-value",
        password: "password-value",
        req: {
          body: {
            identityToken: "identity-token-value",
            newPassword: "new-password-value",
            refreshToken: "refresh-token-value",
          },
          headers: {
            authorization: "Bearer access-token-value",
          },
        },
      },
      "redaction test",
    );

    const output = lines.join("");
    expect(output).not.toContain("api-key-value");
    expect(output).not.toContain("admin-api-token-value");
    expect(output).not.toContain("apple-billing-private-key-value");
    expect(output).not.toContain("authorization-code-value");
    expect(output).not.toContain("identity-token-value");
    expect(output).not.toContain("pepper-value");
    expect(output).not.toContain("new-password-value");
    expect(output).not.toContain("password-value");
    expect(output).not.toContain("refresh-token-value");
    expect(output).not.toContain("access-token-value");
    expect(output).toContain("[REDACTED]");
  });

  it("correlates structured logs with the active trace without adding user data", () => {
    const lines: string[] = [];
    const logger = pino(
      createLoggerOptions("info", () => ({
        spanId: "bbbbbbbbbbbbbbbb",
        traceFlags: 1,
        traceId: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      })),
      {
        write(chunk: string): void {
          lines.push(chunk);
        },
      },
    );

    logger.info("trace correlation test");

    const record = JSON.parse(lines.join("")) as Record<string, unknown>;
    expect(record.traceId).toBe("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    expect(record.spanId).toBe("bbbbbbbbbbbbbbbb");
    expect(record).not.toHaveProperty("userId");
  });

  it("removes query values and dynamic identifiers from request URLs", () => {
    const lines: string[] = [];
    const logger = pino(createLoggerOptions("info"), {
      write(chunk: string): void {
        lines.push(chunk);
      },
    });
    const sessionId = "9d7e1c2b-6f4a-4cf8-916b-c11ca3128fb1";

    logger.info(
      {
        req: {
          method: "DELETE",
          url: `/v1/auth/sessions/${sessionId}?credential=query-secret`,
        },
      },
      "request URL sanitation test",
    );

    const output = lines.join("");
    expect(output).toContain("/v1/auth/sessions/:id");
    expect(output).not.toContain(sessionId);
    expect(output).not.toContain("query-secret");
  });
});
