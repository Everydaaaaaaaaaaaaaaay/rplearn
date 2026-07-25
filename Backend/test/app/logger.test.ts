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
        password: "password-value",
        req: {
          body: {
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
    expect(output).not.toContain("password-value");
    expect(output).not.toContain("refresh-token-value");
    expect(output).not.toContain("access-token-value");
    expect(output).toContain("[REDACTED]");
  });
});
