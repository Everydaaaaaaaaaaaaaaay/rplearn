import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { newEntityId } from "../../shared/id.js";

export class GuestRepository {
  constructor(private readonly database: DatabaseResource) {}

  async resolve(
    installationHash: string,
  ): Promise<{ userId: string; tokenVersion: number }> {
    return this.database.sql.begin(async (sql) => {
      await sql`select pg_advisory_xact_lock(hashtextextended(${`guest:${installationHash}`}, 0))`;
      const [existing] = await sql<
        {
          user_id: string;
          claimed_at: string | null;
          token_version: number;
          status: string;
        }[]
      >`
        select g.user_id::text, g.claimed_at::text, u.token_version, u.status
        from app.guest_installations g join app.users u on u.id = g.user_id
        where installation_hash = ${installationHash} for update of g, u
      `;
      if (existing) {
        if (existing.claimed_at !== null || existing.status !== "active") {
          throw new AppError({
            code: "GUEST_ALREADY_CLAIMED",
            message: "This journey has been saved to an account. Sign in to continue.",
            statusCode: 403,
          });
        }
        return { userId: existing.user_id, tokenVersion: existing.token_version };
      }
      const userId = newEntityId();
      await sql`insert into app.users (id) values (${userId})`;
      await sql`insert into app.guest_installations (user_id, installation_hash) values (${userId}, ${installationHash})`;
      return { userId, tokenVersion: 0 };
    });
  }
}
