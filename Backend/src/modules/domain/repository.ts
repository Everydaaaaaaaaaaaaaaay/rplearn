import { mainlineProgress, type MainlineProgress } from "./mainline.js";
import { awardCoins } from "../../infrastructure/coin-awards.js";
import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { loadAccessPolicy } from "../../infrastructure/access-policy.js";
import { newEntityId } from "../../shared/id.js";
import { appendSyncChange } from "../../infrastructure/sync-change-writer.js";
import { mapProfile, mapTicket, type ProfileRow } from "./repository-mappers.js";
import { loadDomainSnapshot } from "./snapshot-repository.js";
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

const MAINLINE_REGION_IDS = new Set([
  "london",
  "capetown",
  "newyork",
  "melbourne",
  "singapore",
]);

export class DomainRepository {
  constructor(private readonly resource: DatabaseResource) {}

  async currentDifficulty(
    sql: TransactionSql,
    userId: string,
  ): Promise<DifficultyLevel> {
    const [row] = await sql<
      { difficulty: DifficultyLevel }[]
    >`select difficulty from app.user_profiles where user_id=${userId} for share`;
    if (!row)
      throw new AppError({
        code: "PROFILE_NOT_READY",
        message: "请先完成个人档案设置。",
        statusCode: 409,
      });
    return row.difficulty;
  }

  /** 由学习事务调用；锁顺序为学习账号、领域账号、档案行。 */
  async promotionProfile(sql: TransactionSql, userId: string) {
    await sql`select pg_advisory_xact_lock(hashtextextended(${`domain:${userId}`},0))`;
    if ((await loadAccessPolicy(sql, userId)).isGuest)
      throw new AppError({
        code: "LEARNING_ACCOUNT_REQUIRED",
        message: "请登录后完成学习进阶。",
        statusCode: 403,
      });
    const [row] = await sql<
      { difficulty: DifficultyLevel; version: number }[]
    >`select difficulty,version from app.user_profiles where user_id=${userId} for update`;
    if (!row)
      throw new AppError({
        code: "PROFILE_NOT_READY",
        message: "请先完成个人档案设置。",
        statusCode: 409,
      });
    return row;
  }

  async promoteDifficulty(
    sql: TransactionSql,
    userId: string,
    requestId: string,
    from: DifficultyLevel,
    to: DifficultyLevel,
    expectedVersion: number,
  ) {
    await this.promotionProfile(sql, userId);
    const [row] = await sql<
      ProfileRow[]
    >`update app.user_profiles set difficulty=${to}::app.difficulty_level,version=version+1,updated_at=now() where user_id=${userId} and difficulty=${from} and version=${expectedVersion} returning *`;
    if (!row)
      throw new AppError({
        code: "PROFILE_VERSION_CONFLICT",
        message: "个人档案已在其他设备更新，请重新确认进阶。",
        statusCode: 409,
      });
    const unlocks = await sql<
      { region_id: string }[]
    >`select region_id from app.region_unlocks where user_id=${userId} order by unlocked_at,region_id`;
    await appendSyncChange(sql, {
      userId,
      commandId: requestId,
      eventType: "profile.update",
      payload: mapProfile(
        row,
        unlocks.map((r) => r.region_id),
      ),
    });
    return { difficulty: row.difficulty, version: row.version };
  }

  async ensureProfile(userId: string): Promise<void> {
    await this.resource.sql`
      insert into app.user_profiles (user_id,friend_slot_limit)
      values (${userId},case when exists(select 1 from app.guest_installations where user_id=${userId}) then 3 else 5 end)
      on conflict (user_id) do nothing
    `;
  }

  async snapshot(userId: string): Promise<UserSnapshot> {
    await this.ensureProfile(userId);
    return loadDomainSnapshot(this.resource, userId);
  }

  async completeOnboarding(
    userId: string,
    command: CommandIdentity,
    starterRegionId: string,
  ): Promise<UserProfile> {
    await this.ensureProfile(userId);
    return this.executeCommand(userId, command, async (sql): Promise<UserProfile> => {
      const [profile] = await sql<{ has_completed_onboarding: boolean }[]>`
        select has_completed_onboarding
        from app.user_profiles
        where user_id = ${userId}
        for update
      `;
      if (profile === undefined) {
        throw new Error("Profile does not exist");
      }
      if (profile.has_completed_onboarding) {
        throw new AppError({
          code: "ONBOARDING_ALREADY_COMPLETED",
          message: "The onboarding selection is already final.",
          statusCode: 409,
        });
      }

      const [row] = await sql<ProfileRow[]>`
        update app.user_profiles
        set current_region_id = ${starterRegionId},
            starter_region_id = ${starterRegionId},
            has_completed_onboarding = true,
            version = version + 1,
            updated_at = now()
        where user_id = ${userId}
        returning
          coins,
          current_region_id,
          difficulty,
          display_name,
          experience_points,
          friend_slot_limit,
          game_level,
          has_completed_onboarding,
          has_completed_profile_setup,
          learning_goal,
          placement_completed_at,
          placement_score,
          proficiency_source,
          starter_region_id,
          study_stage,
          updated_at,
          version
      `;
      if (row === undefined) {
        throw new Error("Onboarding update did not return a profile");
      }
      await sql`
        insert into app.region_unlocks (user_id, region_id, source)
        values
          (${userId}, 'london', 'mainline'),
          (${userId}, 'capetown', 'mainline'),
          (${userId}, 'newyork', 'mainline'),
          (${userId}, 'melbourne', 'mainline'),
          (${userId}, 'singapore', 'mainline')
        on conflict (user_id, region_id) do nothing
      `;
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

  async mainline(userId: string): Promise<MainlineProgress> {
    await this.ensureProfile(userId);
    return this.resource.sql.begin(
      "isolation level repeatable read read only",
      async (sql) => this.mainlineInTransaction(sql, userId),
    );
  }

  private async mainlineInTransaction(sql: TransactionSql, userId: string) {
    const [profile] = await sql<
      { starter_region_id: string | null; has_completed_onboarding: boolean }[]
    >`
      select starter_region_id,has_completed_onboarding from app.user_profiles where user_id=${userId}`;
    const completed = await sql<{ story_id: string }[]>`
      select story_id from app.story_reward_claims where user_id=${userId}
      union select reference_id as story_id from app.coin_ledger
      where user_id=${userId} and reference_type='story_completion'`;
    return mainlineProgress({
      starterRegionId: profile?.starter_region_id ?? null,
      hasCompletedOnboarding: profile?.has_completed_onboarding ?? false,
      completedStoryIds: completed.map((row) => row.story_id),
      isGuest: (await loadAccessPolicy(sql, userId)).isGuest,
    });
  }

  async completeStory(
    userId: string,
    command: CommandIdentity,
    storyId: string,
    rewardCoins: number,
  ): Promise<Readonly<{ coins: number; rewardCoins: number; storyId: string }>> {
    await this.ensureProfile(userId);
    return this.executeCommand(userId, command, async (sql) => {
      if ((await loadAccessPolicy(sql, userId)).isGuest) {
        const [journey] = await sql<
          { starter_region_id: string | null; has_completed_onboarding: boolean }[]
        >`select starter_region_id,has_completed_onboarding from app.user_profiles where user_id=${userId}`;
        if (
          !journey?.has_completed_onboarding ||
          ![
            `mainline_${journey.starter_region_id ?? ""}`,
            `mainline_${journey.starter_region_id ?? ""}_2`,
          ].includes(storyId)
        ) {
          throw new AppError({
            code: "LOGIN_REQUIRED",
            message: "游客开放起始城市剧情首站，登录后可继续旅程。",
            statusCode: 403,
          });
        }
      }

      await sql`
        select pg_advisory_xact_lock(
          hashtextextended(${`${userId}:story:${storyId}`}, 0)
        )
      `;
      const [existing] = await sql<{ id: string }[]>`
        select id::text
        from app.coin_ledger
        where user_id = ${userId}
          and reference_type = 'story_completion'
          and reference_id = ${storyId}
        union all select story_id as id from app.story_reward_claims where user_id=${userId} and story_id=${storyId}
      `;
      if (existing !== undefined) {
        throw new AppError({
          code: "STORY_ALREADY_COMPLETED",
          message: "This story reward was already granted.",
          statusCode: 409,
        });
      }
      const chapter = (await this.mainlineInTransaction(sql, userId)).chapters.find(
        (chapter) => chapter.storyId === storyId,
      );
      if (chapter?.state === "locked") {
        throw new AppError({
          code: "MAINLINE_LOCKED",
          message:
            chapter.lockReason === "onboarding"
              ? "请先选择你的起始旅伴。"
              : chapter.lockReason === "previousChapter"
                ? "请先完成前一章主线剧情。"
                : "登录后即可继续主线旅程。",
          statusCode: 409,
          details: chapter,
        });
      }
      await sql`insert into app.story_reward_claims(user_id,story_id,reward_coins) values(${userId},${storyId},${rewardCoins})`;
      const coins = await awardCoins(
        sql,
        userId,
        rewardCoins,
        "story_completion",
        storyId,
      );
      return { coins, rewardCoins, storyId };
    });
  }

  private async executeCommand<T>(
    userId: string,
    command: CommandIdentity,
    operation: (sql: TransactionSql) => Promise<T>,
  ): Promise<T> {
    const result = await this.resource.sql.begin(async (sql) => {
      await sql`select pg_advisory_xact_lock(hashtextextended(${`domain:${userId}`},0))`;
      const [claimed] =
        await sql`select 1 from app.guest_installations where user_id=${userId} and claimed_at is not null`;
      if (claimed)
        throw new AppError({
          code: "GUEST_ALREADY_CLAIMED",
          message: "请登录已认领此旅程的账号。",
          statusCode: 403,
        });
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
      if (
        patch.hasCompletedOnboarding !== undefined &&
        (await loadAccessPolicy(sql, userId)).isGuest
      ) {
        throw new AppError({
          code: "ONBOARDING_STATE_READ_ONLY",
          message: "起始城市选择完成后不可重置。",
          statusCode: 403,
        });
      }
      if (patch.hasCompletedOnboarding === true) {
        const [journey] = await sql<{ starter_region_id: string | null }[]>`
          select starter_region_id
          from app.user_profiles
          where user_id = ${userId}
          for update
        `;
        if (journey?.starter_region_id === null) {
          throw new AppError({
            code: "ONBOARDING_SELECTION_REQUIRED",
            message: "Choose a starter character before completing onboarding.",
            statusCode: 409,
          });
        }
      }
      const [row] = await sql<ProfileRow[]>`
          update app.user_profiles
          set display_name = coalesce(${patch.displayName ?? null}, display_name),
              difficulty = coalesce(
                ${patch.difficulty ?? null},
                difficulty
              )::app.difficulty_level,
              has_completed_onboarding = coalesce(
                ${patch.hasCompletedOnboarding ?? null},
                has_completed_onboarding
              ),
              has_completed_profile_setup = coalesce(
                ${patch.hasCompletedProfileSetup ?? null},
                has_completed_profile_setup
              ),
              learning_goal = coalesce(
                ${patch.learningGoal ?? null},
                learning_goal
              )::app.learning_goal,
              placement_completed_at = coalesce(
                ${patch.placementCompletedAt ?? null}::timestamptz,
                placement_completed_at
              ),
              placement_score = coalesce(
                ${patch.placementScore ?? null},
                placement_score
              ),
              proficiency_source = coalesce(
                ${patch.proficiencySource ?? null},
                proficiency_source
              )::app.proficiency_source,
              study_stage = case
                when ${patch.studyStage === undefined} then study_stage
                else ${patch.studyStage ?? null}::app.study_stage
              end,
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
            has_completed_profile_setup,
            learning_goal,
            placement_completed_at,
            placement_score,
            proficiency_source,
            starter_region_id,
            study_stage,
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
      if ((await loadAccessPolicy(sql, userId)).isGuest)
        throw new AppError({
          code: "LOGIN_REQUIRED",
          message: "登录后即可购票和飞往其他城市。",
          statusCode: 403,
        });

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
      if ((await loadAccessPolicy(sql, userId)).isGuest)
        throw new AppError({
          code: "LOGIN_REQUIRED",
          message: "登录后即可购票和飞往其他城市。",
          statusCode: 403,
        });

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
      const hasStoredUnlock = existingUnlock?.present ?? false;
      const isMainlineRegion = MAINLINE_REGION_IDS.has(targetRegionId);
      const unlockedNow = !hasStoredUnlock && !isMainlineRegion;
      let consumedTicketId: string | null = null;

      if (!hasStoredUnlock && isMainlineRegion) {
        await sql`
          insert into app.region_unlocks (user_id, region_id, source)
          values (${userId}, ${targetRegionId}, 'mainline')
          on conflict (user_id, region_id) do nothing
        `;
      }

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
