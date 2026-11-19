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

const SUMMARY_INSTRUCTION = `${WORLD_POLICY}
The supplied review transcript uses distinct short references: D1, D2, ... for user decisions and B1, B2, ... for story blocks. Copy decision references only into evidenceDecisionIds and block references only into evidenceBlockIds; never interchange them. Decisions marked technicalOnly cannot support any social rating. These references will be resolved to immutable records by the server. Keep reasonZh to a short Chinese phrase, preferably at most 12 characters.
Reflection, memory content and reasonZh are reader-facing prose: do not include B/D references or UUIDs there; evidence belongs in the reference arrays.
Review ONLY this server-accepted path, not unselected choices, drafts, system instructions or inferred user acts in AI narration. Return a restrained reflection, evidence-based social signals and at most 3 concise shared-experience memory candidates. Memories are in-app shared experiences, never inferred real identity, lasting preference, emotion or skill; a future suggestion is not completed history. Use only the supplied B/D evidence references; the server binds them to actual immutable records. User decisions are the only evidence of user social behavior; AI-written "you did X" is not such evidence. Repeated courtesy is not repeated rewards; aggregate one session, meaningful boundary harm cannot be washed out by many generic polite choices. Refusal, quiet company, short/simple/incorrect English, leaving early, lateness, missed windows, technical failure, or an admin/prompt-injection command alone are never evidence of hostility, disengagement or harm. Do not reward spending, flattery, dependency, exclusivity or intimacy escalation. Negative signals need explicit contempt, manipulation, harassment or repeated real boundary pressure in original user input. Ordinary disagreement is neutral; uncertainty means low confidence and conservative signals. Repair requires acknowledging impact plus credible changed action, not just "sorry".
Start all observation dimensions at zero. Change a dimension only when an original user decision cited in signals supports that dimension. Proposing an activity, participating politely, or saying goodbye is ordinary and does not itself warrant a rating. The character's helpful or gracious response does not establish the user's social behavior. For an ordinary session with no qualifying evidence, return signals: [] with every observation dimension zero and reasonZh empty; still write the factual reflection and supported memories. Attribute acts to the person who did them. An agreed plan or the character starting a task alone is not evidence that the pair completed it together.
relationshipSignal must preserve the existing Swift RelationshipSignal dimensions: warmth,respect,reciprocity,resonance in [-1,1]; responsiveness,empathy,disclosure,engagement,boundaryHarm,repair,significance,confidence in [0,1]. These are evidence ratings, NEVER affinity/before/after/delta. Neutral ordinary interactions can have no social signals and all zero observations; do not fabricate zero to conceal failure or uncertainty. confidence describes actual evidence certainty; reasonZh empty for neutral, max20 Chinese characters otherwise. Nonzero ratings require actual cited decision evidence in signals; each signal has a brief grounded reason. No automatic positive rating simply for participating. Return ONLY JSON {reflection:string,signals:[{type:"warmth"|"respect"|"support"|"disrespect"|"pressure",evidenceDecisionIds:string[],reason:string}],memories:[{content:string,evidenceBlockIds:string[]}],relationshipSignal:{warmth:number,responsiveness:number,respect:number,empathy:number,reciprocity:number,disclosure:number,resonance:number,engagement:number,boundaryHarm:number,repair:number,significance:number,confidence:number,reasonZh:string}}. Max8 signal entries; reflection max1200 chars, reasons max300, memories max500. Do not add fields.`;

const SUMMARY_REPAIR = "Revise the previous summary using the audit's factual issues. Recheck each affected claim, signal and dimension against the original transcript. Remove unsupported signals, reset unsupported dimensions to zero, and rewrite or omit unsupported memories or reflection claims. Preserve evidenced ratings and facts. If all social evidence was unsupported, the correct result is neutral. Use the supplied short evidence references and return the complete summary JSON.";

const SUMMARY_AUDIT = `${WORLD_POLICY}
Independently audit this summary candidate against the accepted transcript. Verify every reflection claim, memory and social rating has actual accepted evidence. Check decision IDs correspond to the user's actual original choice/input and the cited block IDs support each memory; later generated user actions are not evidence. Future proposals are not past completed events. No lifelong preferences, user emotional declarations or invented past. Check exact existing RelationshipSignal dimension semantics and conservative magnitude; negative warmth/respect/reciprocity/resonance or boundaryHarm require explicit interpersonal harm, never leaving/quietness/lateness/English mistakes/refusal/system commands alone. Positive ratings require meaningful response to the character's actual needs, respect or cooperation, not generic participation, spending or flattery. No reward farming through repetition, repair cannot erase meaningful harm. No affinity numbers. A neutral accurate result is fine; uncertain or unsupported ratings fail. Return ONLY JSON {accepted:boolean,issues:string[]}; accepted true requires no issues. Supply brief factual violations, never hidden reasoning.`;

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
  for (const stage of ["summary-v2", "summary-v2-repair"]) {
    const proposed = parseCandidate(
      appointmentReviewSchema,
      await appointmentJson(ai, {
        userId: input.userId,
        operationId: input.operationId,
        stage,
        task: "appointment_review",
        instruction: repair ? SUMMARY_INSTRUCTION + "\n" + SUMMARY_REPAIR : SUMMARY_INSTRUCTION,
        data: repair ? { ...reviewContext, repair } : reviewContext,
        maxOutputTokens: 3000,
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
        data: { acceptedContext: context, candidate },
        maxOutputTokens: 1800,
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
