import { v7 as uuidv7 } from "uuid";
import { z } from "zod";

export const entityIdSchema = z
  .string()
  .regex(
    /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    "Expected a UUIDv7 identifier",
  );

export type EntityId = z.infer<typeof entityIdSchema>;

export function newEntityId(): EntityId {
  return entityIdSchema.parse(uuidv7());
}
