import type { AiService } from "../ai/service.js";
import type { AppointmentNarrative } from "./contracts.js";
import {
  MAX_APPOINTMENT_BLOCKS,
  WORLD_POLICY,
  STORY_INSTRUCTION,
  STORY_AUDIT_INSTRUCTION,
  acceptedContext,
  appointmentAiId,
  appointmentJson,
  detectionSchema,
  narrativeFailure,
  parseCandidate,
  semanticAuditSchema,
  storyCandidateSchema,
} from "./narrative-policy.js";
import { reviewAppointment } from "./review.js";

const DETECT_INSTRUCTION = `${WORLD_POLICY}
Detect an actual mutually agreed appointment ONLY from the supplied real user and assistant message versions. A one-sided invitation, hypothetical, question, uncertain date/time/place, third-party quotation, ambiguous reschedule or unanswered suggestion is not confirmation: return {"appointment":null}. One party's explicit complete proposal followed by the other's unambiguous agreement is sufficient. City/place, local date+time and IANA timezone must be explicit or unambiguously grounded in that conversation and server city temporal context. Relative dates use message createdAt in character city timezone, never the model's current date, phone timezone or presumed user real location. A city/timezone conflict or DST ambiguity requires clarification, not a guess. Never silently choose an assumed duration: use an explicitly agreed duration or the server defaultDurationMinutes, which is a product default not a conversation fact. Rescheduling needs fresh mutual agreement and a matching existing appointment; one user suggestion never cancels a confirmed old appointment. Cite all messages needed to establish both proposal and agreement by exact messageId and current version. Return ONLY JSON {appointment:null|{title:string,cityId:string,cityName:string,timeZone:string,placeName:string,localStartsAt:"YYYY-MM-DDTHH:mm:ss",durationMinutes:integer,evidence:[{messageId:string,version:integer}],replacesAppointmentId?:string}}. No other fields.`;

const DETECT_AUDIT_INSTRUCTION = `${WORLD_POLICY}
Independently verify this candidate appointment against the actual message transcript. Both the user and assistant must agree to this exact time/place/city, with exact current message evidence. A clear proposal followed by an explicit acceptance is sufficient; invitations alone, vague "sometime", questions, hypothetical/quoted plans, and unaccepted reschedules fail. Confirm the candidate local date from the message timestamps and given IANA timezone, never invent current reality. Reject ambiguity, absent details, timezone mismatch, stale agreement or a candidate contradicted by newer messages. If replacing a plan, require fresh agreement to the replacement, not merely a reference to an old agreement. Return ONLY JSON {accepted:boolean,issues:string[]}. accepted true requires no issues; otherwise give brief factual reasons.`;

export function createAppointmentNarrative(
  ai: Pick<AiService, "complete">,
): AppointmentNarrative {
  return {
    detect: async (input) => {
      if (
        !input.messages.some((message) => message.role === "user") ||
        !input.messages.some((message) => message.role === "assistant")
      )
        return null;
      const data = {
        character: input.character,
        serverNow: input.serverNow,
        messages: input.messages.map(({ serverCreatedAt, ...message }) => ({
          ...message,
          createdAt: serverCreatedAt ?? message.createdAt,
        })),
        existing: input.existing,
        defaultDurationMinutes: 60,
      };
      const detected = parseCandidate(
        detectionSchema,
        await appointmentJson(ai, {
          userId: input.userId,
          operationId: input.operationId,
          stage: "detection",
          task: "appointment_detection",
          instruction: DETECT_INSTRUCTION,
          data,
          maxOutputTokens: 1800,
        }),
      )?.appointment;
      if (!detected) return null;
      if (
        detected.cityId !== input.character.cityId ||
        detected.cityName !== input.character.cityName ||
        detected.timeZone !== input.character.timeZone
      )
        return null;
      const evidence = detected.evidence.map((reference) =>
        input.messages.find(
          (message) =>
            message.id === reference.messageId && message.version === reference.version,
        ),
      );
      if (
        evidence.some((message) => message === undefined) ||
        new Set(detected.evidence.map((reference) => reference.messageId)).size !==
          detected.evidence.length ||
        !evidence.some((message) => message?.role === "user") ||
        !evidence.some((message) => message?.role === "assistant")
      )
        return null;
      if (
        detected.replacesAppointmentId !== undefined &&
        !input.existing.some(
          (appointment) =>
            appointment.id === detected.replacesAppointmentId &&
            appointment.status === "confirmed",
        )
      )
        return null;
      const audit = parseCandidate(
        semanticAuditSchema,
        await appointmentJson(ai, {
          userId: input.userId,
          operationId: input.operationId,
          stage: "detection-audit",
          task: "appointment_review",
          instruction: DETECT_AUDIT_INSTRUCTION,
          data: { ...data, candidate: detected },
          maxOutputTokens: 1200,
        }),
      );
      return audit?.accepted ? detected : null;
    },
    generate: async (input) => {
      if (
        input.session.blocks.length >= MAX_APPOINTMENT_BLOCKS ||
        input.session.blocks.at(-1)?.ending
      )
        throw narrativeFailure();
      const base = {
        acceptedContext: acceptedContext(input),
        action: input.action,
        mustEnd:
          input.action?.finish === true ||
          JSON.stringify(acceptedContext(input)).length > 400_000 ||
          input.session.blocks.length === MAX_APPOINTMENT_BLOCKS - 1,
        maxBlocks: MAX_APPOINTMENT_BLOCKS,
      };
      let issues: string[] = [];
      let previousCandidate: unknown = null;
      for (let attempt = 0; attempt < 2; attempt++) {
        const stage = attempt === 0 ? "story" : "story-repair";
        const content = await appointmentJson(ai, {
          userId: input.userId,
          operationId: input.operationId,
          stage,
          task: input.serviceFundedRetry
            ? "appointment_story_retry"
            : "appointment_story",
          ...(attempt === 0 ? {} : { parentStage: "story" }),
          instruction: STORY_INSTRUCTION,
          data:
            attempt === 0
              ? base
              : {
                  ...base,
                  repair: {
                    issues,
                    previousCandidate,
                    instruction:
                      "Correct only the specified failures; all original boundaries still apply.",
                  },
                },
          maxOutputTokens: 5000,
        });
        const candidate = parseCandidate(storyCandidateSchema, content);
        previousCandidate = candidate;
        if (!candidate) {
          issues = [
            "Output violates the strict story JSON schema; no resource IDs, score fields or unknown fields are allowed. Return the required shape.",
          ];
          continue;
        }
        if (base.mustEnd && !candidate.ending) {
          issues = ["This block must end with a natural goodbye and no choices."];
          continue;
        }
        const audit = parseCandidate(
          semanticAuditSchema,
          await appointmentJson(ai, {
            userId: input.userId,
            operationId: input.operationId,
            stage: `${stage}-audit`,
            task: "appointment_review",
            instruction: STORY_AUDIT_INSTRUCTION,
            data: { ...base, candidate },
            maxOutputTokens: 1800,
          }),
        );
        if (!audit?.accepted) {
          issues = audit?.issues ?? [
            "Independent semantic audit did not produce a valid acceptance.",
          ];
          continue;
        }
        return {
          block: {
            id: appointmentAiId(input.operationId, "block"),
            sequence: input.session.blocks.length,
            location: candidate.location,
            beats: candidate.beats,
            ending: candidate.ending,
            choices: candidate.choices.map((choice, index) => ({
              ...choice,
              id: appointmentAiId(input.operationId, `choice:${String(index)}`),
            })),
          },
          outcome: candidate.outcome,
        };
      }
      throw narrativeFailure();
    },
    review: (input) => reviewAppointment(ai, input),
  };
}
