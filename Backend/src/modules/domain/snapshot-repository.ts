import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { mapProfile, mapTicket, type ProfileRow } from "./repository-mappers.js";
import type { FirstArrival, TicketSource, TicketType, UserSnapshot } from "./types.js";

function mapFirstArrival(row: {
  arrived_at: string;
  from_region_id: string;
  id: string;
  to_region_id: string;
}): FirstArrival {
  return {
    arrivedAt: new Date(row.arrived_at).toISOString(),
    fromRegionId: row.from_region_id,
    id: row.id,
    toRegionId: row.to_region_id,
  };
}

export async function loadDomainSnapshot(
  resource: DatabaseResource,
  userId: string,
): Promise<UserSnapshot> {
  const [profile] = await resource.sql<ProfileRow[]>`
    select
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

  const unlockRows = await resource.sql<{ region_id: string }[]>`
    select region_id
    from app.region_unlocks
    where user_id = ${userId}
    order by unlocked_at, region_id
  `;
  const ticketRows = await resource.sql<
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
  const firstArrivalRows = await resource.sql<
    {
      arrived_at: string;
      from_region_id: string;
      id: string;
      to_region_id: string;
    }[]
  >`
    select
      id,
      from_region_id,
      to_region_id,
      arrived_at
    from (
      select distinct on (to_region_id)
        id::text,
        from_region_id,
        to_region_id,
        traveled_at as arrived_at
      from app.travel_records
      where user_id = ${userId}
        and ticket_item_id is not null
      order by to_region_id, traveled_at, id
    ) as first_arrivals
    order by arrived_at, id
  `;

  return {
    firstArrivals: firstArrivalRows.map(mapFirstArrival),
    profile: mapProfile(
      profile,
      unlockRows.map((row) => row.region_id),
    ),
    tickets: ticketRows.map(mapTicket),
  };
}
