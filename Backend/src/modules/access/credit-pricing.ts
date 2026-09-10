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
  usdToCny?: string;
}>;

export type ExternalCreditPriceResolver = (
  provider: string,
  model: string,
  at: Date,
) => Promise<CreditPrice>;

function ceilDivide(value: bigint, divisor: bigint): bigint {
  return (value + divisor - 1n) / divisor;
}

export function openRouterCreditPrice(
  model: string,
  pricing: Readonly<{
    cachedInputPriceUsd: string | null;
    completionPriceUsd: string;
    observedAt: string;
    promptPriceUsd: string;
  }>,
  usdToCny: string,
  at: Date,
): CreditPrice {
  const fx = decimalUnits(usdToCny, 6);
  const rate = (usdPerToken: string): string =>
    String(ceilDivide(decimalUnits(usdPerToken, 18) * fx, 1_000_000_000_000_000n));
  return {
    cachedInput: rate(pricing.cachedInputPriceUsd ?? pricing.promptPriceUsd),
    effectiveFrom: pricing.observedAt,
    input: rate(pricing.promptPriceUsd),
    model,
    output: rate(pricing.completionPriceUsd),
    pricedAt: at.toISOString(),
    provider: "openrouter",
    source: "https://openrouter.ai/api/v1/models",
    usdToCny,
    version: `openrouter-catalog-${pricing.observedAt}`,
  };
}
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
/** Only provider-documented aliases may share an accounting identity.
 * https://api-docs.deepseek.com/zh-cn/quick_start/pricing (verified 2026-09-11).
 * Pro and arbitrary model names must never be silently treated as Flash.
 */
export function creditModelMatches(
  price: CreditPrice,
  returnedModel: string | null,
): boolean {
  if (returnedModel === price.model) return true;
  const flashAliases = [
    "deepseek-flash",
    "deepseek-v4-flash",
    "deepseek-v4-flash-vision-exp",
  ];
  return (
    price.provider === "deepseek" &&
    returnedModel !== null &&
    flashAliases.includes(price.model) &&
    flashAliases.includes(returnedModel)
  );
}

export function exactCreditCost(
  price: CreditPrice,
  usage: AiUsage | null,
): bigint | null {
  if (!usage) return null;
  if (price.usdToCny !== undefined && usage.providerCostUsd !== undefined) {
    try {
      return ceilDivide(
        decimalUnits(usage.providerCostUsd, 12) * decimalUnits(price.usdToCny, 6),
        1_000_000_000n,
      );
    } catch {
      return null;
    }
  }
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
