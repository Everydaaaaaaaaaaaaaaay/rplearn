import type { DatabaseResource } from "../../db/client.js";
import type {
  AppointmentContextReader,
  AppointmentNarrative,
  AppointmentSettlementWriter,
} from "./contracts.js";
import { AppointmentRepository } from "./repository.js";
export function createAppointmentService(
  database: DatabaseResource,
  context: AppointmentContextReader,
  narrative: AppointmentNarrative,
  settlement: AppointmentSettlementWriter,
  now?: () => Date,
) {
  return new AppointmentRepository(database, context, narrative, settlement, now);
}
