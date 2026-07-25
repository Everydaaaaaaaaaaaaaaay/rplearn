import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { newEntityId } from "../../shared/id.js";
import { appendSyncChange } from "../sync/change-writer.js";
import type {
  CommandIdentity,
  DifficultyLevel,
  ProfilePatch,
  Ticket,
  TicketSource,
  TicketType,
  TravelResult,
  UserProfile,
  UserSnapshot,
} from "./types.js";

type ProfileRow = Readonly<{
  coins: number;
  current_region_id: string;
  difficulty: DifficultyLevel;
  display_name: string;
  experience_points: number;
  friend_slot_limit: number;
  game_level: number;
  has_completed_onboarding: boolean;
  quiz_globally_enabled: boolean;
  updated_at: string;
  version: number;
}>;

function mapProfile(
  row: ProfileRow,
  unlockedRegionIds: readonly string[],
): UserProfile {
  return {
    coins: row.coins,
    currentRegionId: row.current_region_id,
    difficulty: row.difficulty,
    displayName: row.display_name,
    experiencePoints: row.experience_points,
    friendSlotLimit: row.friend_slot_limit,
    gameLevel: row.game_level,
    hasCompletedOnboarding: row.has_completed_onboarding,
    quizGloballyEnabled: row.quiz_globally_enabled,
    unlockedRegionIds,
    updatedAt: new Date(row.updated_at).toISOString(),
    version: row.version,
  };
}

function mapTicket(row: {
  country_code: string | null;
  created_at: string;
  id: string;
  source: TicketSource;
  type: TicketType;
}): Ticket {
  return {
    countryCode: row.country_code,
    createdAt: new Date(row.created_at).toISOString(),
    id: row.id,
    source: row.source,
    type: row.type,
  };
}

export class DomainRepository {
  constructor(private readonly resource: DatabaseResource) {}

  async ensureProfile(userId: string): Promise<void> {
    await this.resource.sql.begin(async (sql) => {
      await sql`
        insert into app.user_profiles (user_id)
        values (${userId})
        on conflict (user_id) do nothing
      `;
      await sql`
        insert into app.region_unlocks (user_id, region_id, source)
        values (${userId}, 'london', 'initial')
        on conflict (user_id, region_id) do nothing
      `;
    });
  }

  async snapshot(userId: string): Promise<UserSnapshot> {
    await this.ensureProfile(userId);
    const [profile] = await this.resource.sql<ProfileRow[]>`
      select
        coins,
        current_region_id,
        difficulty,
        display_name,
        experience_points,
        friend_slot_limit,
        game_level,
        has_completed_onboarding,
        quiz_globally_enabled,
        updated_at,
        version
      from app.user_profiles
      where user_id = ${userId}
    `;
    if (profile === undefined) {
      throw new AppError({
        code: "PROFILE_NOT_FOUND",
        expose: false,
        message: "The user profile does not exist.",
        statusCode: 500,
      });
    }

    const unlockRows = await this.resource.sql<{ region_id: string }[]>`
      select region_id
      from app.region_unlocks
      where user_id = ${userId}
      order by unlocked_at, region_id
    `;
    const ticketRows = await this.resource.sql<
      {
        country_code: string | null;
        created_at: string;
        id: string;
        source: TicketSource;
        type: TicketType;
      }[]
    >`
      select
        id::text,
        type,
        country_code,
        source,
        created_at
      from app.inventory_items
      where user_id = ${userId}
        and status = 'available'
      order by created_at, id
    `;

    return {
      profile: mapProfile(
        profile,
        unlockRows.map((row) => row.region_id),
      ),
      tickets: ticketRows.map(mapTicket),
    };
  }

  async claimStarterTicket(userId: string, command: CommandIdentity): Promise<Ticket> {
    await this.ensureProfile(userId);
    return this.executeCommand(userId, command, async (sql) => {
      const [profile] = await sql<{ has_completed_onboarding: boolean }[]>`
        select has_completed_onboarding
        from app.user_profiles
        where user_id = ${userId}
        for update
      `;
      if (profile?.has_completed_onboarding !== true) {
        throw new AppError({
          code: "ONBOARDING_REQUIRED",
          message: "Complete onboarding before claiming the starter ticket.",
          statusCode: 409,
        });
      }
      const [existing] = await sql<{ id: string }[]>`
        select id::text
        from app.inventory_items
        where user_id = ${userId}
          and source = 'quest'
          and source_reference_id = 'starter-ticket-v1'
      `;
      if (existing !== undefined) {
        throw new AppError({
          code: "STARTER_TICKET_ALREADY_CLAIMED",
          message: "The starter ticket was already claimed.",
          statusCode: 409,
        });
      }
      const [ticket] = await sql<
        {
          country_code: string | null;
          created_at: string;
          id: string;
          source: TicketSource;
          type: TicketType;
        }[]
      >`
        insert into app.inventory_items (
          id,
          user_id,
          type,
          country_code,
          source,
          source_reference_id
        )
        values (
          ${newEntityId()},
          ${userId},
          'universal',
          null,
          'quest',
          'starter-ticket-v1'
        )
        returning id::text, type, country_code, source, created_at
      `;
      if (ticket === undefined) {
        throw new Error("Starter ticket insert did not return a row");
      }
      return mapTicket(ticket);
    });
  }

  private async executeCommand<T>(
    userId: string,
    command: CommandIdentity,
    operation: (sql: TransactionSql) => Promise<T>,
  ): Promise<T> {
    const result = await this.resource.sql.begin(async (sql) => {
      await sql`
        select pg_advisory_xact_lock(
          hashtextextended(${`${userId}:${command.commandId}`}, 0)
        )
      `;
      const [receipt] = await sql<
        {
          request_hash: string;
          response_text: string;
          route: string;
        }[]
      >`
        select
          request_hash,
          route,
          response::text as response_text
        from app.command_receipts
        where user_id = ${userId}
          and command_id = ${command.commandId}
      `;
      if (receipt !== undefined) {
        if (
          receipt.request_hash !== command.requestHash ||
          receipt.route !== command.route
        ) {
          throw new AppError({
            code: "IDEMPOTENCY_KEY_CONFLICT",
            message: "This idempotency key was already used for a different request.",
            statusCode: 409,
          });
        }
        return JSON.parse(receipt.response_text) as T;
      }

      const response = await operation(sql);
      await appendSyncChange(sql, {
        commandId: command.commandId,
        eventType: command.route,
        payload: response,
        userId,
      });
      await sql`
        insert into app.command_receipts (
          user_id,
          command_id,
          route,
          request_hash,
          response
        )
        values (
          ${userId},
          ${command.commandId},
          ${command.route},
          ${command.requestHash},
          ${JSON.stringify(response)}::jsonb
        )
      `;
      return response;
    });
    return result as T;
  }

  async updateProfile(
    userId: string,
    command: CommandIdentity,
    patch: ProfilePatch,
  ): Promise<UserProfile> {
    await this.ensureProfile(userId);
    return this.executeCommand(userId, command, async (sql): Promise<UserProfile> => {
      const [row] = await sql<ProfileRow[]>`
          update app.user_profiles
          set display_name = coalesce(${patch.displayName ?? null}, display_name),
              difficulty = coalesce(
                ${patch.difficulty ?? null},
                difficulty
              )::app.difficulty_level,
              quiz_globally_enabled = coalesce(
                ${patch.quizGloballyEnabled ?? null},
                quiz_globally_enabled
              ),
              has_completed_onboarding = coalesce(
                ${patch.hasCompletedOnboarding ?? null},
                has_completed_onboarding
              ),
              version = version + 1,
              updated_at = now()
          where user_id = ${userId}
            and version = ${patch.expectedVersion}
          returning
            coins,
            current_region_id,
            difficulty,
            display_name,
            experience_points,
            friend_slot_limit,
            game_level,
            has_completed_onboarding,
            quiz_globally_enabled,
            updated_at,
            version
        `;
      if (row === undefined) {
        throw new AppError({
          code: "PROFILE_VERSION_CONFLICT",
          message: "The profile changed on another device.",
          statusCode: 409,
        });
      }
      const unlocks = await sql<{ region_id: string }[]>`
          select region_id
          from app.region_unlocks
          where user_id = ${userId}
          order by unlocked_at, region_id
        `;
      return mapProfile(
        row,
        unlocks.map((unlock) => unlock.region_id),
      );
    });
  }

  async purchaseTicket(
    userId: string,
    command: CommandIdentity,
    type: TicketType,
    countryCode?: string,
  ): Promise<Readonly<{ coins: number; ticket: Ticket }>> {
    await this.ensureProfile(userId);
    return this.executeCommand(userId, command, async (sql) => {
      const normalizedCountry =
        type === "country" ? countryCode?.toUpperCase() : undefined;
      if (type === "country" && normalizedCountry === undefined) {
        throw new AppError({
          code: "COUNTRY_CODE_REQUIRED",
          message: "A country ticket requires a country code.",
          statusCode: 400,
        });
      }
      const price = type === "universal" ? 500 : 300;
      const [profile] = await sql<{ coins: number }[]>`
        select coins
        from app.user_profiles
        where user_id = ${userId}
        for update
      `;
      if (profile === undefined || profile.coins < price) {
        throw new AppError({
          code: "INSUFFICIENT_COINS",
          message: "There are not enough coins to buy this ticket.",
          statusCode: 409,
        });
      }

      const ticketId = newEntityId();
      const newBalance = profile.coins - price;
      await sql`
        update app.user_profiles
        set coins = ${newBalance},
            version = version + 1,
            updated_at = now()
        where user_id = ${userId}
      `;
      await sql`
        insert into app.coin_ledger (
          id,
          user_id,
          delta,
          balance_after,
          reason,
          reference_type,
          reference_id
        )
        values (
          ${newEntityId()},
          ${userId},
          ${-price},
          ${newBalance},
          'ticket_purchase',
          'inventory_item',
          ${ticketId}
        )
      `;
      const [ticket] = await sql<
        {
          country_code: string | null;
          created_at: string;
          id: string;
          source: TicketSource;
          type: TicketType;
        }[]
      >`
        insert into app.inventory_items (
          id,
          user_id,
          type,
          country_code,
          source,
          source_reference_id
        )
        values (
          ${ticketId},
          ${userId},
          ${type},
          ${normalizedCountry ?? null},
          'purchase',
          ${ticketId}
        )
        returning id::text, type, country_code, source, created_at
      `;
      if (ticket === undefined) {
        throw new Error("Ticket insert did not return a row");
      }
      return {
        coins: newBalance,
        ticket: mapTicket(ticket),
      };
    });
  }

  async grantCoins(
    userId: string,
    command: CommandIdentity,
    amount: number,
    reason: string,
  ): Promise<Readonly<{ coins: number }>> {
    await this.ensureProfile(userId);
    return this.executeCommand(userId, command, async (sql) => {
      const [profile] = await sql<{ coins: number }[]>`
        select coins
        from app.user_profiles
        where user_id = ${userId}
        for update
      `;
      if (profile === undefined) {
        throw new Error("Profile does not exist");
      }
      const newBalance = profile.coins + amount;
      const ledgerId = newEntityId();
      await sql`
        update app.user_profiles
        set coins = ${newBalance},
            version = version + 1,
            updated_at = now()
        where user_id = ${userId}
      `;
      await sql`
        insert into app.coin_ledger (
          id,
          user_id,
          delta,
          balance_after,
          reason,
          reference_type,
          reference_id
        )
        values (
          ${ledgerId},
          ${userId},
          ${amount},
          ${newBalance},
          ${reason},
          'command',
          ${command.commandId}
        )
      `;
      return { coins: newBalance };
    });
  }

  async grantTicket(
    userId: string,
    command: CommandIdentity,
    type: TicketType,
    source: TicketSource,
    countryCode?: string,
  ): Promise<Ticket> {
    await this.ensureProfile(userId);
    return this.executeCommand(userId, command, async (sql) => {
      const normalizedCountry =
        type === "country" ? countryCode?.toUpperCase() : undefined;
      if (type === "country" && normalizedCountry === undefined) {
        throw new AppError({
          code: "COUNTRY_CODE_REQUIRED",
          message: "A country ticket requires a country code.",
          statusCode: 400,
        });
      }
      const [ticket] = await sql<
        {
          country_code: string | null;
          created_at: string;
          id: string;
          source: TicketSource;
          type: TicketType;
        }[]
      >`
        insert into app.inventory_items (
          id,
          user_id,
          type,
          country_code,
          source,
          source_reference_id
        )
        values (
          ${newEntityId()},
          ${userId},
          ${type},
          ${normalizedCountry ?? null},
          ${source},
          ${command.commandId}
        )
        returning id::text, type, country_code, source, created_at
      `;
      if (ticket === undefined) {
        throw new Error("Ticket insert did not return a row");
      }
      return mapTicket(ticket);
    });
  }

  async travel(
    userId: string,
    command: CommandIdentity,
    targetRegionId: string,
    ticketId?: string,
  ): Promise<TravelResult> {
    await this.ensureProfile(userId);
    return this.executeCommand(userId, command, async (sql) => {
      const [profile] = await sql<{ current_region_id: string; version: number }[]>`
        select current_region_id, version
        from app.user_profiles
        where user_id = ${userId}
        for update
      `;
      if (profile === undefined) {
        throw new Error("Profile does not exist");
      }
      if (profile.current_region_id === targetRegionId) {
        throw new AppError({
          code: "ALREADY_IN_REGION",
          message: "The user is already in this region.",
          statusCode: 409,
        });
      }

      const [target] = await sql<{ country_code: string; id: string }[]>`
        select id, country_code
        from app.regions
        where id = ${targetRegionId}
          and is_active = true
      `;
      if (target === undefined) {
        throw new AppError({
          code: "REGION_NOT_FOUND",
          message: "The destination region does not exist.",
          statusCode: 404,
        });
      }

      const [existingUnlock] = await sql<{ present: boolean }[]>`
        select exists (
          select 1
          from app.region_unlocks
          where user_id = ${userId}
            and region_id = ${targetRegionId}
        ) as present
      `;
      const unlockedNow = !(existingUnlock?.present ?? false);
      let consumedTicketId: string | null = null;

      if (unlockedNow) {
        if (ticketId === undefined) {
          throw new AppError({
            code: "TICKET_REQUIRED",
            message: "A usable ticket is required to unlock this region.",
            statusCode: 409,
          });
        }
        const [ticket] = await sql<
          {
            country_code: string | null;
            id: string;
            status: "available" | "consumed" | "revoked";
            type: TicketType;
          }[]
        >`
          select id::text, type, country_code, status
          from app.inventory_items
          where id = ${ticketId}
            and user_id = ${userId}
          for update
        `;
        const usable =
          ticket?.status === "available" &&
          (ticket.type === "universal" ||
            ticket.country_code?.toUpperCase() === target.country_code.toUpperCase());
        if (!usable) {
          throw new AppError({
            code: "TICKET_NOT_USABLE",
            message: "The selected ticket cannot unlock this region.",
            statusCode: 409,
          });
        }
        await sql`
          update app.inventory_items
          set status = 'consumed',
              consumed_at = now(),
              consumed_for_region_id = ${targetRegionId}
          where id = ${ticket.id}
        `;
        await sql`
          insert into app.region_unlocks (user_id, region_id, source)
          values (${userId}, ${targetRegionId}, 'ticket')
        `;
        consumedTicketId = ticket.id;
      }

      await sql`
        insert into app.region_unlocks (user_id, region_id, source)
        values (${userId}, ${profile.current_region_id}, 'travel_history')
        on conflict (user_id, region_id) do nothing
      `;
      const [updated] = await sql<{ version: number }[]>`
        update app.user_profiles
        set current_region_id = ${targetRegionId},
            version = version + 1,
            updated_at = now()
        where user_id = ${userId}
        returning version
      `;
      const travelId = newEntityId();
      const [record] = await sql<{ traveled_at: string }[]>`
        insert into app.travel_records (
          id,
          user_id,
          from_region_id,
          to_region_id,
          ticket_item_id
        )
        values (
          ${travelId},
          ${userId},
          ${profile.current_region_id},
          ${targetRegionId},
          ${consumedTicketId}
        )
        returning traveled_at
      `;
      if (record === undefined || updated === undefined) {
        throw new Error("Travel transaction did not return its result");
      }
      return {
        consumedTicketId,
        fromRegionId: profile.current_region_id,
        profileVersion: updated.version,
        toRegionId: targetRegionId,
        travelId,
        traveledAt: new Date(record.traveled_at).toISOString(),
        unlockedNow,
      };
    });
  }
}
