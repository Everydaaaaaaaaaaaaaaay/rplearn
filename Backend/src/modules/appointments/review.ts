import type { AiService } from "../ai/service.js";
import type { AppointmentGenerationContext, AppointmentReview } from "./contracts.js";
import { z } from "zod";
import {
  WORLD_POLICY,
  acceptedContext,
  appointmentJson,
  appointmentReviewSchema,
  isTechnicalOnlyAction,
  narrativeFailure,
  parseCandidate,
} from "./narrative-policy.js";

const REVIEW_EVIDENCE_POLICY = `${WORLD_POLICY}
The accepted transcript uses D1, D2, ... for decisions and B1, B2, ... for story blocks. A decision was made at blockId and received its response in resultBlockId. Its input is direct evidence of what the user said or explicitly did. A proposal is evidence of a proposal only. Attribute actions to their actual actors and keep changes over time, including changes of role in make-believe, in order. Exclude unselected choices, drafts, invented user actions, inferred feelings and claims about the user's real life or lasting traits.
Never rate technicalOnly decisions. Asking, playing along, being quiet, declining, ordinary politeness or disagreement, speaking imperfect English, leaving and missing a window are neutral. Start with all numeric observations at zero and reasonZh empty. Change an observation only with a specific original decision showing meaningful cooperation, respect, support, contempt, pressure or similar evidence beyond ordinary participation. Negative ratings require explicit harm or boundary pressure. Repetition, generic compliments, spending, exclusivity and intimacy do not earn ratings. Repair requires acknowledging impact and changing behavior. Ratings describe evidence, never affinity. Confidence measures evidence certainty. A neutral result is valid.`;

const SUMMARY_INSTRUCTION = `${REVIEW_EVIDENCE_POLICY}
Write a brief Simplified Chinese reflection that recalls one or two concrete moments in the story. Avoid a play-by-play transcript, moral, or verdict. If a detailed claim adds little or its evidence is unclear, omit it. Include zero to three brief shared-experience memories, each supported by its cited blocks. Put D references only in evidenceDecisionIds and B references only in evidenceBlockIds. Keep references and internal terminology out of reader-facing prose. reasonZh is at most 20 Chinese characters and empty when no observation is rated.
Return only JSON {reflection:string,signals:[{type:"warmth"|"respect"|"support"|"disrespect"|"pressure",evidenceDecisionIds:string[],reason:string}],memories:[{content:string,evidenceBlockIds:string[]}],relationshipSignal:{warmth:number,responsiveness:number,respect:number,empathy:number,reciprocity:number,disclosure:number,resonance:number,engagement:number,boundaryHarm:number,repair:number,significance:number,confidence:number,reasonZh:string}}. Warmth, respect, reciprocity and resonance are in [-1,1]. All other numeric dimensions are in [0,1]. Max 8 signals. With no qualifying decision use signals: [], all observations zero, and no reason. Do not add fields.`;

const SUMMARY_REPAIR = "Address the audit findings using the original transcript and the same D/B references. Drop unsupported detail or ratings, including an entire memory if needed. Keep the corrected recap brief. Return complete JSON.";

const SUMMARY_AUDIT = `${REVIEW_EVIDENCE_POLICY}
Return only JSON {recapAccepted:boolean,relationship:"accept"|"neutral"|"repair",issues:string[]}. Make the two decisions independently.
recapAccepted: Check the reflection and each proposed memory and citation for concrete discrepancies. One memory may cite multiple blocks; judge their combined evidence. A problem with a rating does not affect this answer.
relationship: First look for a qualifying act by the user in the original decisions, before considering the writer's ratings. If there is none, return "neutral" even when the writer proposed several ratings. A request followed by a refusal alone does not establish pressure. Asking about someone's work and leaving politely are normal participation. If there is qualifying evidence, return "accept" for accurate, cited ratings and "repair" for unsupported or missing ratings.
issues: Give up to four brief corrections for an inaccurate recap or "repair" rating. Otherwise use [].`;

const reviewAuditSchema = z.object({
  recapAccepted: z.boolean(),
  relationship: z.enum(["accept", "neutral", "repair"]),
  issues: z.array(z.string().trim().min(1).max(500)).max(4),
}).strict().refine((audit) => {
  const needsRepair = !audit.recapAccepted || audit.relationship === "repair";
  return needsRepair === (audit.issues.length > 0);
});

const neutralRelationshipSignal = {
  warmth: 0, responsiveness: 0, respect: 0, empathy: 0, reciprocity: 0,
  disclosure: 0, resonance: 0, engagement: 0, boundaryHarm: 0, repair: 0,
  significance: 0, confidence: 0, reasonZh: "",
};

function hasOnlyAcceptedEvidence(
  candidate: AppointmentReview,
  input: AppointmentGenerationContext,
): boolean {
  const blockIds = new Set(input.session.blocks.map((block) => block.id));
  const decisionIds = new Set(
    input.session.decisions
      .filter(
        (decision) =>
          blockIds.has(decision.blockId) && !isTechnicalOnlyAction(decision.input),
      )
      .map((decision) => decision.id),
  );
  return (
    candidate.signals.every((signal) =>
      signal.evidenceDecisionIds.every((id) => decisionIds.has(id)),
    ) &&
    candidate.memories.every((memory) =>
      memory.evidenceBlockIds.every((id) => blockIds.has(id)),
    )
  );
}

export async function reviewAppointment(
  ai: Pick<AiService, "complete">,
  input: AppointmentGenerationContext,
): Promise<AppointmentReview> {
  if (!input.session.blocks.at(-1)?.ending)
    throw narrativeFailure("APPOINTMENT_REVIEW_REJECTED");
  const paragraphHistory = input.session.blocks.some(({ presentation }) => presentation === "paragraphs");
  const context = acceptedContext(input, paragraphHistory);
  const blockReferences = new Map(input.session.blocks.map((block, index) => [block.id, `B${String(index + 1)}`]));
  const resultBlockReferences = new Map(
    input.session.blocks.slice(0, -1).map((block, index) => [block.id, `B${String(index + 2)}`]),
  );
  const decisionReferences = new Map(input.session.decisions.map((decision, index) => [decision.id, `D${String(index + 1)}`]));
  const canonicalBlocks = new Map([...blockReferences].map(([id, reference]) => [reference, id]));
  const canonicalDecisions = new Map([...decisionReferences].map(([id, reference]) => [reference, id]));
  const reviewSession = {
    blocks: context.session.blocks.map((block) => ({
      ...(paragraphHistory ? { location: block.location, beats: block.beats } : block),
      id: blockReferences.get(block.id),
    })),
    decisions: context.session.decisions.map((decision) => ({
      ...(paragraphHistory ? { input: decision.input } : decision),
      id: decisionReferences.get(decision.id),
      blockId: blockReferences.get(decision.blockId),
      resultBlockId: resultBlockReferences.get(decision.blockId),
      technicalOnly: isTechnicalOnlyAction(decision.input),
    })),
  };
  // The recap needs the transcript and its evidence IDs. The persona and scheduling
  // metadata used by the writer would take budget away from reviewing the scene.
  const reviewContext = paragraphHistory
    ? { character: { name: context.character.name }, session: reviewSession }
    : { ...context, session: { ...context.session, ...reviewSession } };
  const readable = (text: string) => text.replace(/\b[BD]\d+\b/g, (reference) => {
    if (!canonicalDecisions.has(reference) && !canonicalBlocks.has(reference)) return reference;
    const chinese = /\p{Script=Han}/u.test(text);
    const kind = reference.startsWith("D") ? (chinese ? "回应" : "response ") : (chinese ? "片段" : "section ");
    return kind + reference.slice(1);
  });
  let repair: { issues: string[]; previousCandidate: AppointmentReview; neutral: boolean } | undefined;
  // Expired review leases can retain operation IDs across a deployment.
  // Use new stage IDs for the revised prompts to avoid conflicts with old receipts.
  const summaryStage = paragraphHistory ? "summary-v6-paragraphs" : "summary-v6";
  const instruction = paragraphHistory
    ? SUMMARY_INSTRUCTION + "\nA rating needs a qualifying act by the user in a cited decision. Do not rate the companion's speech, boundary, or reaction. For routine participation and ordinary proposals use the neutral result."
    : SUMMARY_INSTRUCTION;
  for (const stage of [summaryStage, summaryStage + "-repair"]) {
    const draft = parseCandidate(
      appointmentReviewSchema,
      await appointmentJson(ai, {
        userId: input.userId,
        operationId: input.operationId,
        stage,
        task: "appointment_review",
        requiredAppointmentStep: true,
        instruction: repair
          ? instruction + "\n" + SUMMARY_REPAIR +
            (repair.neutral ? "\nThe independent audit found no qualifying user act. Keep the relationship neutral and correct only the recap." : "")
          : instruction,
        data: repair
          ? { ...reviewContext, repair: paragraphHistory ? { issues: repair.issues } : repair }
          : reviewContext,
        maxOutputTokens: paragraphHistory ? 850 : 1600,
      }),
    );
    if (!draft) throw narrativeFailure("APPOINTMENT_REVIEW_REJECTED");
    const proposed = repair?.neutral
      ? { ...draft, signals: [], relationshipSignal: neutralRelationshipSignal }
      : draft;
    const candidate = {
      ...proposed,
      signals: proposed.signals.map((signal) => ({
        ...signal,
        evidenceDecisionIds: signal.evidenceDecisionIds.map(
          (id) => canonicalDecisions.get(id) ?? id,
        ),
      })),
      memories: proposed.memories.map((memory) => ({
        ...memory,
        evidenceBlockIds: memory.evidenceBlockIds.map((id) => canonicalBlocks.get(id) ?? id),
      })),
    };
    if (!hasOnlyAcceptedEvidence(candidate, input))
      throw narrativeFailure("APPOINTMENT_REVIEW_REJECTED");
    const signal = candidate.relationshipSignal;
    const observationValues = [
      signal.warmth,
      signal.responsiveness,
      signal.respect,
      signal.empathy,
      signal.reciprocity,
      signal.disclosure,
      signal.resonance,
      signal.engagement,
      signal.boundaryHarm,
      signal.repair,
      signal.significance,
    ];
    if (candidate.signals.length === 0 && observationValues.some((value) => value !== 0))
      throw narrativeFailure("APPOINTMENT_REVIEW_REJECTED");
    const audit = parseCandidate(
      reviewAuditSchema,
      await appointmentJson(ai, {
        userId: input.userId,
        operationId: input.operationId,
        stage: stage + "-audit",
        task: "appointment_review",
        requiredAppointmentStep: true,
        instruction: SUMMARY_AUDIT,
        data: { acceptedContext: reviewContext, candidate: proposed },
        maxOutputTokens: paragraphHistory ? 450 : 800,
      }),
    );
    if (!audit) break;
    if (audit.recapAccepted && audit.relationship !== "repair") {
      const neutral = audit.relationship === "neutral";
      return {
        ...candidate,
        signals: neutral ? [] : candidate.signals,
        reflection: readable(candidate.reflection),
        memories: candidate.memories.map((memory) => ({
          ...memory,
          content: readable(memory.content),
        })),
        relationshipSignal: neutral ? neutralRelationshipSignal : {
          ...candidate.relationshipSignal,
          reasonZh: Array.from(readable(candidate.relationshipSignal.reasonZh)).slice(0, 20).join(""),
        },
      };
    }
    repair = {
      issues: audit.issues,
      previousCandidate: proposed,
      neutral: audit.relationship === "neutral",
    };
  }
  throw narrativeFailure("APPOINTMENT_REVIEW_REJECTED");
}
