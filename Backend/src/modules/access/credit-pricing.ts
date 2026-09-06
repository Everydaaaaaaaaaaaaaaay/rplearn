import { readFileSync } from "node:fs";
import type { AiMessage, AiUsage } from "../ai/types.js";
import { AppError } from "../../shared/errors.js";
import { isBeijingPeak, priceBookSchema, type PriceBook } from "./cost-report.js";

// One yuan = 10^9 ledger units; one displayed credit = 10^6 units.
// Only presentation converts to Number. Ledger arithmetic never uses binary floats.
export const UNITS_PER_CREDIT = 1_000_000n;
export function decimalUnits(value: string, places: number): bigint {
  if (!/^\d+(\.\d+)?$/.test(value)) throw new Error("Invalid nonnegative decimal");
  const [whole = "0", fraction = ""] = value.split(".");
  if (fraction.length > places) throw new Error("Price exceeds ledger precision");
  return BigInt(whole + fraction.padEnd(places, "0"));
}
export type CreditPrice = Readonly<{
  version: string;
  source: string;
  provider: string;
  model: string;
  effectiveFrom: string;
  pricedAt: string;
  input: string;
  cachedInput: string;
  output: string;
}>;
export function loadCreditPriceBook(): PriceBook {
  return priceBookSchema.parse(
    JSON.parse(
      readFileSync(new URL("../../../config/ai-prices.json", import.meta.url), "utf8"),
    ),
  );
}
export function creditPrice(
  book: PriceBook,
  provider: string,
  model: string,
  at: Date,
  peak = false,
): CreditPrice {
  const row = book.models
    .filter(
      (p) =>
        p.provider === provider &&
        p.model === model &&
        Date.parse(p.effectiveFrom) <= at.getTime(),
    )
    .sort((a, b) => b.effectiveFrom.localeCompare(a.effectiveFrom))[0];
  // Future adapters must supply their own billing semantics before they can spend credits.
  if (!row || provider !== "deepseek")
    throw new AppError({
      code: "AI_PRICE_UNAVAILABLE",
      message: "模型价格尚未核验，暂不能使用。",
      statusCode: 503,
    });
  const multiplier = decimalUnits(
    String(peak || isBeijingPeak(at) ? 1 : row.offPeakMultiplier),
    6,
  );
  const rate = (value: number): string => {
    const scaled = decimalUnits(String(value), 9) * multiplier;
    if (scaled % 1_000_000_000_000n !== 0n)
      throw new Error("Token price exceeds nanoyuan precision");
    return String(scaled / 1_000_000_000_000n);
  };
  return {
    version: book.version,
    source: book.source,
    provider,
    model,
    effectiveFrom: row.effectiveFrom,
    pricedAt: at.toISOString(),
    input: rate(row.inputPerMillion),
    cachedInput: rate(row.cachedInputPerMillion),
    output: rate(row.outputPerMillion),
  };
}
export function exactCreditCost(
  price: CreditPrice,
  usage: AiUsage | null,
): bigint | null {
  if (!usage) return null;
  const {
    inputTokens: input,
    outputTokens: output,
    totalTokens: total,
    cacheHitTokens: hit,
    cacheMissTokens: miss,
  } = usage;
  if (
    ![input, output, total, hit, miss].every(
      (n) => typeof n === "number" && Number.isSafeInteger(n) && n >= 0,
    )
  )
    return null;
  if (
    hit === undefined ||
    miss === undefined ||
    hit + miss !== input ||
    input + output !== total
  )
    return null;
  return (
    BigInt(hit) * BigInt(price.cachedInput) +
    BigInt(miss) * BigInt(price.input) +
    BigInt(output) * BigInt(price.output)
  );
}
export function reservationCost(
  price: CreditPrice,
  messages: readonly AiMessage[],
  maxOutput: number,
): bigint {
  // Conservative UTF-8 envelope, including chat template overhead. This is a hold,
  // not measured usage; overruns are recorded in full and require operational review.
  const inputBound = messages.reduce(
    (n, m) => n + Buffer.byteLength(m.content, "utf8") + 64,
    1024,
  );
  return (
    BigInt(inputBound) * BigInt(price.input) + BigInt(maxOutput) * BigInt(price.output)
  );
}
export const displayCredits = (units: bigint): number =>
  Number(units) / Number(UNITS_PER_CREDIT);
