import type { DatabaseResource } from "../../db/client.js";
import { OutingRepository } from "./outing-repository.js";
import type { OutingLocationReader, OutingService } from "./outing-types.js";

export function createOutingService(
  database: DatabaseResource,
  location: OutingLocationReader,
  roll?: () => number,
): OutingService {
  return new OutingRepository(database, location, roll);
}
