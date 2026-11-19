import type { AiService } from "../ai/service.js";
import type { AppointmentGenerationContext, AppointmentReview } from "./contracts.js";
import {
  WORLD_POLICY,
  acceptedContext,
  appointmentJson,
  appointmentReviewSchema,
  isTechnicalOnlyAction,
  narrativeFailure,
  parseCandidate,
  semanticAuditSchema,
} from "./narrative-policy.js";

const REVIEW_EVIDENCE_POLICY = `${WORLD_POLICY}
The accepted transcript uses D1, D2, ... for decisions and B1, B2, ... for story blocks. A decision was made at blockId and received its response in resultBlockId. Its input is direct evidence of what the user said or explicitly did. A proposal is evidence of a proposal only. Attribute actions to their actual actors and keep changes over time, including changes of role in make-believe, in order. Exclude unselected choices, drafts, invented user actions, inferred feelings and claims about the user's real life or lasting traits.
Never rate technicalOnly decisions. Asking, playing along, being quiet, declining, ordinary politeness or disagreement, speaking imperfect English, leaving and missing a window are neutral. Start with all numeric observations at zero and reasonZh empty. Change an observation only with a specific original decision showing meaningful cooperation, respect, support, contempt, pressure or similar evidence beyond ordinary participation. Negative ratings require explicit harm or boundary pressure. Repetition, generic compliments, spending, exclusivity and intimacy do not earn ratings. Repair requires acknowledging impact and changing behavior. Ratings describe evidence, never affinity. Confidence measures evidence certainty. A neutral result is valid.`;

const SUMMARY_INSTRUCTION = `${REVIEW_EVIDENCE_POLICY}
Write a brief Simplified Chinese reflection that recalls one or two concrete moments in the story. Avoid a play-by-play transcript, moral, or verdict. If a detailed claim adds little or its evidence is unclear, omit it. Include zero to three brief shared-experience memories, each supported by its cited blocks. Put D references only in evidenceDecisionIds and B references only in evidenceBlockIds. Keep references and internal terminology out of reader-facing prose. reasonZh is at most 20 Chinese characters and empty when no observation is rated.
Return only JSON {reflection:string,signals:[{type:"warmth"|"respect"|"support"|"disrespect"|"pressure",evidenceDecisionIds:string[],reason:string}],memories:[{content:string,evidenceBlockIds:string[]}],relationshipSignal:{warmth:number,responsiveness:number,respect:number,empathy:number,reciprocity:number,disclosure:number,resonance:number,engagement:number,boundaryHarm:number,repair:number,significance:number,confidence:number,reasonZh:string}}. Warmth, respect, reciprocity and resonance are in [-1,1]. All other numeric dimensions are in [0,1]. Max 8 signals. With no qualifying decision use signals: [], all observations zero, and no reason. Do not add fields.`;

const SUMMARY_REPAIR = "Address the audit findings using the original transcript and the same D/B references. Drop unsupported detail or ratings, including an entire memory if needed. Keep the corrected recap brief. Return complete JSON.";

const SUMMARY_AUDIT = `${REVIEW_EVIDENCE_POLICY}
Independently check every claim, memory and social observation against the transcript. One memory may cite multiple blocks; judge their combined evidence and linked decisions. Accept supported paraphrases, compact recaps and neutral results. Flag only concrete unsupported claims, ratings, or evidence references. Return only JSON {accepted:boolean,issues:string[]}. List at most four actionable issues using the same D/B references. If accepted, issues is empty.`;

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
  const context = acceptedContext(input);
  const blockReferences = new Map(input.session.blocks.map((block, index) => [block.id, `B${String(index + 1)}`]));
  const resultBlockReferences = new Map(
    input.session.blocks.slice(0, -1).map((block, index) => [block.id, `B${String(index + 2)}`]),
  );
  const decisionReferences = new Map(input.session.decisions.map((decision, index) => [decision.id, `D${String(index + 1)}`]));
  const canonicalBlocks = new Map([...blockReferences].map(([id, reference]) => [reference, id]));
  const canonicalDecisions = new Map([...decisionReferences].map(([id, reference]) => [reference, id]));
  const reviewContext = {
    ...context,
    session: {
      ...context.session,
      blocks: context.session.blocks.map((block) => ({ ...block, id: blockReferences.get(block.id) })),
      decisions: context.session.decisions.map((decision) => ({
        ...decision, id: decisionReferences.get(decision.id),
        blockId: blockReferences.get(decision.blockId),
        resultBlockId: resultBlockReferences.get(decision.blockId),
        technicalOnly: isTechnicalOnlyAction(decision.input),
      })),
    },
  };
  const readable = (text: string) => text.replace(/\b[BD]\d+\b/g, (reference) => {
    if (!canonicalDecisions.has(reference) && !canonicalBlocks.has(reference)) return reference;
    const chinese = /\p{Script=Han}/u.test(text);
    const kind = reference.startsWith("D") ? (chinese ? "回应" : "response ") : (chinese ? "片段" : "section ");
    return kind + reference.slice(1);
  });
  let repair: { issues: string[]; previousCandidate: AppointmentReview } | undefined;
  // Expired review leases can retain operation IDs across a deployment.
  // Use new stage IDs for the revised prompts to avoid conflicts with old receipts.
  for (const stage of ["summary-v3", "summary-v3-repair"]) {
    const proposed = parseCandidate(
      appointmentReviewSchema,
      await appointmentJson(ai, {
        userId: input.userId,
        operationId: input.operationId,
        stage,
        task: "appointment_review",
        instruction: repair ? SUMMARY_INSTRUCTION + "\n" + SUMMARY_REPAIR : SUMMARY_INSTRUCTION,
        data: repair ? { ...reviewContext, repair } : reviewContext,
        maxOutputTokens: 1600,
      }),
    );
    if (!proposed) throw narrativeFailure("APPOINTMENT_REVIEW_REJECTED");
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
      semanticAuditSchema,
      await appointmentJson(ai, {
        userId: input.userId,
        operationId: input.operationId,
        stage: stage + "-audit",
        task: "appointment_review",
        instruction: SUMMARY_AUDIT,
        data: { acceptedContext: reviewContext, candidate: proposed },
        maxOutputTokens: 800,
      }),
    );
    if (!audit) break;
    if (audit.accepted) {
      return {
        ...candidate,
        reflection: readable(candidate.reflection),
        memories: candidate.memories.map((memory) => ({
          ...memory,
          content: readable(memory.content),
        })),
        relationshipSignal: {
          ...candidate.relationshipSignal,
          reasonZh: Array.from(readable(candidate.relationshipSignal.reasonZh)).slice(0, 20).join(""),
        },
      };
    }
    repair = { issues: audit.issues, previousCandidate: proposed };
  }
  throw narrativeFailure("APPOINTMENT_REVIEW_REJECTED");
}
