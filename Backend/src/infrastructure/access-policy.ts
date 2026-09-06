import type { Sql, TransactionSql } from "postgres";

export type ActorAccessPolicy = Readonly<{
  isGuest: boolean;
  plan: "guest" | "free" | "pro" | "max";
  friendSlotLimit: number;
  canTravel: boolean;
  canContinueStories: boolean;
  quotaWindow: "lifetime" | "day" | "month";
  chatLimit: number;
  voiceSecondsLimit: number;
  advancedLimit: number;
  policyVersion: number;
  provisional: boolean;
}>;

const nonnegative = (value: unknown, fallback: number, maximum: number): number =>
  typeof value === "number" &&
  Number.isSafeInteger(value) &&
  value >= 0 &&
  value <= maximum
    ? value
    : fallback;

/** Shared transactional policy projection. Existing purchased feature flags remain authoritative. */
export async function loadAccessPolicy(
  sql: Sql | TransactionSql,
  userId: string,
): Promise<ActorAccessPolicy> {
  const [identity] = await sql<{ guest: boolean }[]>`
    select exists(select 1 from app.guest_installations where user_id = ${userId})
      or exists(select 1 from app.ai_guest_principals where user_id = ${userId}) as guest
  `;
  const [plan] = await sql<{ tier: string; flags: Record<string, unknown> }[]>`
    select p.tier, p.feature_flags as flags from app.billing_plans p
    where p.is_active and (p.tier = 'free' or (${identity?.guest !== true} and exists (
      select 1 from app.entitlement_grants g where g.user_id = ${userId} and g.plan_id = p.id
      and g.status in ('active', 'grace') and (g.valid_until is null or g.valid_until > now())
    ))) order by p.rank desc limit 1
  `;
  const [configuration] = await sql<{ value: Record<string, unknown> }[]>`
    select value from app.service_metadata where key = 'guest-access-policy-v1'
  `;
  const isGuest = identity?.guest === true;
  const flags = isGuest ? (configuration?.value ?? {}) : (plan?.flags ?? {});
  const code = isGuest
    ? "guest"
    : plan?.tier === "pro"
      ? "max"
      : plan?.tier === "plus"
        ? "pro"
        : "free";
  const paid = code === "pro" || code === "max";
  return {
    isGuest,
    plan: code,
    friendSlotLimit: nonnegative(
      flags.friendSlotLimit,
      isGuest ? 3 : code === "free" ? 5 : code === "pro" ? 10 : 20,
      200,
    ),
    canTravel: !isGuest,
    canContinueStories: !isGuest,
    quotaWindow: isGuest ? "lifetime" : paid ? "month" : "day",
    chatLimit: nonnegative(
      flags.chatLimit,
      isGuest ? 12 : code === "free" ? 30 : code === "pro" ? 1200 : 3600,
      100_000,
    ),
    voiceSecondsLimit: nonnegative(
      flags.voiceSecondsLimit,
      isGuest ? 60 : code === "free" ? 180 : code === "pro" ? 3600 : 14400,
      1_000_000,
    ),
    advancedLimit: nonnegative(
      flags.advancedLimit,
      isGuest ? 1 : code === "free" ? 3 : code === "pro" ? 60 : 180,
      100_000,
    ),
    policyVersion: nonnegative(flags.policyVersion, 1, 1_000_000),
    provisional: flags.provisional !== false,
  };
}
