import { randomUUID } from "node:crypto";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { appendSyncChange } from "../../infrastructure/sync-change-writer.js";
import { authoredUnitSeeds, type UnitTemplate } from "./unit-seeds.js";

const challengeLength = 1000;
const correctPerStar = 10;
const starsPerGrade = 9;
const difficultyLevels = ["primary1", "primary2", "primary3", "primary4", "primary5", "primary6",
  "junior1", "junior2", "junior3", "senior1", "senior2", "senior3"] as const;

function initialGrade(difficulty: string): number {
  const index = difficultyLevels.findIndex(level => level === difficulty);
  if (index >= 0) return index + 1;
  return ["undergraduate", "postgraduate", "advanced"].includes(difficulty) ? 12 : 1;
}

function difficultyForGrade(grade: number): string {
  return difficultyLevels[grade - 1] ?? "primary1";
}

interface AccountRow { grade: number; grade_correct: number; completed_levels: number }
interface CharacterRow { chat_characters: number; active_attempt_id: string | null; role_key: string }
interface AttemptRow {
  id: string; template_id: string; grade: number; answers: Record<string, string>;
  correct_question_ids: string[]; completed_at: string | null; started_at: string;
  payload: UnitTemplate;
}

function fail(code: string, message: string, statusCode = 409): never {
  throw new AppError({ code, message, statusCode });
}

function normalized(answer: string): string {
  return answer.normalize("NFKC").trim().toLocaleLowerCase("en-US")
    .replace(/[.!?。！？，,\s]+/gu, " ").trim();
}

function publicTemplate(template: UnitTemplate) {
  return {
    id: template.id, title: template.title, objective: template.objective,
    grade: template.grade, scene: template.scene,
    questions: template.questions.map(question => ({
      id: question.id, kind: question.kind, prompt: question.prompt, options: question.options,
    })),
  };
}

function attemptView(attempt: AttemptRow) {
  return {
    id: attempt.id, grade: attempt.grade, startedAt: attempt.started_at,
    completedAt: attempt.completed_at,
    template: publicTemplate(attempt.payload),
    answers: attempt.answers,
    correctQuestionIds: attempt.correct_question_ids,
    correctCount: attempt.correct_question_ids.length,
    questionCount: attempt.payload.questions.length,
  };
}

function progress(account: AccountRow, character: CharacterRow) {
  return {
    grade: account.grade,
    gradeCorrect: account.grade_correct,
    stars: Math.min(starsPerGrade, Math.floor(account.grade_correct / correctPerStar)),
    correctPerStar,
    starsPerGrade,
    gradeTarget: correctPerStar * starsPerGrade,
    completedLevels: account.completed_levels,
    chatCharacters: character.chat_characters,
    challengeLength,
    ready: character.chat_characters >= challengeLength && character.active_attempt_id === null,
  };
}

function roleKey(_value: string, characterId: string): string {
  switch (characterId.toLowerCase()) {
    case "8b3a2b24-8a4e-5a73-a2c4-0f5e8f05e001": return "oliver";
    case "8b3a2b24-8a4e-5a73-a2c4-0f5e8f05e002": return "ruby";
    case "8b3a2b24-8a4e-5a73-a2c4-0f5e8f05e003": return "marcus";
    default: return characterId.toLowerCase();
  }
}

export function createUnitLearningService(
  database: DatabaseResource,
  generate?: (roleKey: string, grade: number, characterId: string, userId: string) => Promise<{ template: UnitTemplate; scopeUserId: string | null }>,
) {
  const { sql } = database;
  let seeded: Promise<void> | undefined;
  function ensureSeeds(): Promise<void> {
    seeded ??= (async () => {
      for (const template of authoredUnitSeeds) {
        const version = template.id.startsWith("unit-v2-") ? 2 : 1;
        await sql`insert into app.unit_learning_templates(id,role_key,grade,source,version,payload)
          values(${template.id},${template.roleKey},${template.grade},'authored',${version},${JSON.stringify(template)}::jsonb)
          on conflict(id) do nothing`;
      }
    })().catch((error: unknown) => { seeded = undefined; throw error; });
    return seeded;
  }

  async function ensureRows(userId: string, characterId: string, role: string) {
    const [profile] = await sql<{ difficulty: string }[]>`select difficulty::text as difficulty
      from app.user_profiles where user_id=${userId}`;
    const difficulty = profile?.difficulty ?? "primary1";
    await sql`insert into app.unit_learning_accounts(user_id,grade,source_difficulty)
      values(${userId},${initialGrade(difficulty)},${difficulty})
      on conflict(user_id) do update set grade=${initialGrade(difficulty)},grade_correct=0,
        source_difficulty=${difficulty},updated_at=now()
      where app.unit_learning_accounts.source_difficulty is distinct from ${difficulty}`;
    await sql`insert into app.unit_learning_characters(user_id,character_id,role_key)
      values(${userId},${characterId},${roleKey(role, characterId)}) on conflict do nothing`;
  }

  async function read(userId: string, characterId: string, role: string) {
    await ensureRows(userId, characterId, role);
    const [accounts, characters, attempts] = await Promise.all([
      sql<AccountRow[]>`select grade,grade_correct,completed_levels from app.unit_learning_accounts where user_id=${userId}`,
      sql<CharacterRow[]>`select chat_characters,active_attempt_id,role_key from app.unit_learning_characters where user_id=${userId} and character_id=${characterId}`,
      sql<AttemptRow[]>`select a.id,a.template_id,a.grade,a.answers,a.correct_question_ids,a.completed_at,a.started_at,t.payload
        from app.unit_learning_attempts a join app.unit_learning_templates t on t.id=a.template_id
        where a.user_id=${userId} and a.character_id=${characterId} order by a.started_at desc`,
    ]);
    const account = accounts[0], character = characters[0];
    if (!account || !character) fail("UNIT_STATE_UNAVAILABLE", "Learning state is unavailable.", 503);
    const active = attempts.find(attempt => attempt.id === character.active_attempt_id);
    return {
      progress: progress(account, character),
      active: active ? attemptView(active) : null,
      history: attempts.filter(attempt => attempt.completed_at !== null).map(attemptView),
    };
  }

  async function recordMessage(userId: string, input: {
    characterId: string; roleKey: string; messageId: string; role: "user" | "assistant"; characterCount: number;
  }) {
    const count = input.characterCount;
    if (!Number.isInteger(count) || count < 1 || count > 4000)
      fail("INVALID_UNIT_MESSAGE", "Message length is invalid.", 400);
    await ensureRows(userId, input.characterId, input.roleKey);
    return sql.begin(async tx => {
      const inserted = await tx`insert into app.unit_learning_messages(user_id,message_id,character_id,character_count)
        values(${userId},${input.messageId},${input.characterId},${count}) on conflict do nothing returning message_id`;
      const [account] = await tx<AccountRow[]>`select grade,grade_correct,completed_levels from app.unit_learning_accounts where user_id=${userId}`;
      const [character] = await tx<CharacterRow[]>`select chat_characters,active_attempt_id,role_key
        from app.unit_learning_characters where user_id=${userId} and character_id=${input.characterId} for update`;
      if (!account || !character) fail("UNIT_STATE_UNAVAILABLE", "Learning state is unavailable.", 503);
      if (inserted.length && character.chat_characters < challengeLength && character.active_attempt_id === null) {
        character.chat_characters = Math.min(challengeLength, character.chat_characters + count);
        await tx`update app.unit_learning_characters set chat_characters=${character.chat_characters}
          where user_id=${userId} and character_id=${input.characterId}`;
      }
      return progress(account, character);
    });
  }

  async function start(userId: string, characterId: string, role: string, contentVersion: 1 | 2 = 1, generatedCount = 0) {
    await ensureSeeds();
    await ensureRows(userId, characterId, role);
    const selected = await sql.begin(async tx => {
      const [account] = await tx<AccountRow[]>`select grade,grade_correct,completed_levels
        from app.unit_learning_accounts where user_id=${userId} for update`;
      const [character] = await tx<CharacterRow[]>`select chat_characters,active_attempt_id,role_key
        from app.unit_learning_characters where user_id=${userId} and character_id=${characterId} for update`;
      if (!account || !character) fail("UNIT_STATE_UNAVAILABLE", "Learning state is unavailable.", 503);
      if (character.active_attempt_id) return character.active_attempt_id;
      if (character.chat_characters < challengeLength) fail("UNIT_NOT_READY", "Keep chatting to unlock a challenge.");
      const templates = await tx<{ id: string }[]>`select t.id from app.unit_learning_templates t
        where t.role_key=${character.role_key} and t.grade=${account.grade}
          and t.version <= ${contentVersion}
          and (t.scope_user_id is null or t.scope_user_id=${userId})
          and not exists(select 1 from app.unit_learning_attempts a where a.user_id=${userId}
            and a.character_id=${characterId} and a.template_id=t.id)
        order by t.version desc, random() limit 1`;
      const template = templates[0];
      if (!template) return null;
      const id = randomUUID();
      await tx`insert into app.unit_learning_attempts(id,user_id,character_id,template_id,grade)
        values(${id},${userId},${characterId},${template.id},${account.grade})`;
      await tx`update app.unit_learning_characters set active_attempt_id=${id}
        where user_id=${userId} and character_id=${characterId}`;
      return id;
    });
    if (selected === null) {
      if (!generate || generatedCount >= 1) fail("UNIT_POOL_EXHAUSTED", "New unit content is being prepared.", 503);
      const [account] = await sql<AccountRow[]>`select grade,grade_correct,completed_levels
        from app.unit_learning_accounts where user_id=${userId}`;
      if (!account) fail("UNIT_STATE_UNAVAILABLE", "Learning state is unavailable.", 503);
      const key = roleKey(role, characterId);
      const generated = await generate(key, account.grade, characterId, userId);
      const version = contentVersion;
      await sql`insert into app.unit_learning_templates(id,role_key,grade,source,scope_user_id,version,payload)
        values(${generated.template.id},${key},${account.grade},'generated',${generated.scopeUserId},${version},${JSON.stringify(generated.template)}::jsonb)
        on conflict(id) do nothing`;
      return start(userId, characterId, role, contentVersion, generatedCount + 1);
    }
    const state = await read(userId, characterId, role);
    if (state.active?.id !== selected) fail("UNIT_STATE_UNAVAILABLE", "Challenge could not be loaded.", 503);
    return state;
  }

  async function answer(userId: string, attemptId: string, questionId: string, answerText: string) {
    const result = await sql.begin(async tx => {
      const [attempt] = await tx<(AttemptRow & { character_id: string })[]>`select a.id,a.character_id,a.template_id,a.grade,a.answers,
        a.correct_question_ids,a.completed_at,a.started_at,t.payload
        from app.unit_learning_attempts a join app.unit_learning_templates t on t.id=a.template_id
        where a.id=${attemptId} and a.user_id=${userId} for update of a`;
      if (!attempt) fail("UNIT_ATTEMPT_NOT_FOUND", "Challenge was not found.", 404);
      const question = attempt.payload.questions.find(item => item.id === questionId);
      if (!question) fail("UNIT_QUESTION_NOT_FOUND", "Question was not found.", 404);
      if (attempt.answers[questionId] !== undefined && attempt.completed_at === null)
        fail("UNIT_RETRY_AFTER_COMPLETION", "Finish this unit before retrying missed questions.");
      const value = normalized(answerText);
      if (value.length < 1 || value.length > 200 || (question.kind === "choice" && !question.options.some(option => normalized(option) === value)))
        fail("INVALID_UNIT_ANSWER", "Answer is invalid.", 400);
      const correct = value === normalized(question.answer);
      const newlyCorrect = correct && !attempt.correct_question_ids.includes(questionId);
      const answers = { ...attempt.answers, [questionId]: answerText };
      const correctIds = newlyCorrect ? [...attempt.correct_question_ids, questionId] : attempt.correct_question_ids;
      const completed = attempt.completed_at !== null || attempt.payload.questions.every(item => answers[item.id] !== undefined);
      await tx`update app.unit_learning_attempts set answers=${JSON.stringify(answers)}::jsonb,
        correct_question_ids=${correctIds}::text[],
        completed_at=case when ${completed} then coalesce(completed_at,now()) else completed_at end
        where id=${attemptId}`;
      const [account] = await tx<AccountRow[]>`select grade,grade_correct,completed_levels
        from app.unit_learning_accounts where user_id=${userId} for update`;
      if (!account) fail("UNIT_STATE_UNAVAILABLE", "Learning state is unavailable.", 503);
      let levelAdvanced = false;
      const awarded = newlyCorrect && account.grade === attempt.grade;
      if (awarded) {
        const next = account.grade_correct + 1;
        levelAdvanced = next >= correctPerStar * starsPerGrade && account.grade < 12;
        const grade = levelAdvanced ? account.grade + 1 : account.grade;
        const gradeCorrect = levelAdvanced ? 0 : Math.min(90, next);
        await tx`update app.unit_learning_accounts set grade=${grade},grade_correct=${gradeCorrect},
          completed_levels=completed_levels+${levelAdvanced ? 1 : 0},
          source_difficulty=${difficultyForGrade(grade)},updated_at=now() where user_id=${userId}`;
        if (levelAdvanced) {
          await tx`update app.user_profiles set difficulty=${difficultyForGrade(grade)}::app.difficulty_level,
            version=version+1,updated_at=now() where user_id=${userId}`;
          await appendSyncChange(tx, { userId, commandId: randomUUID(),
            eventType: "unit_learning_grade_advanced", payload: { grade } });
        }
      }
      if (completed && attempt.completed_at === null) {
        await tx`update app.unit_learning_characters set active_attempt_id=null,chat_characters=0
          where user_id=${userId} and character_id=${attempt.character_id} and active_attempt_id=${attemptId}`;
      }
      return { characterId: attempt.character_id, correct, newlyCorrect, awarded, completed, levelAdvanced,
        explanation: completed || correct ? question.explanation : null,
        correctAnswer: completed || correct ? question.answer : null };
    });
    const state = await read(userId, result.characterId, "other");
    return { ...result, state };
  }

  async function changeGrade(userId: string, characterId: string, role: string, grade: number) {
    if (!Number.isInteger(grade) || grade < 1 || grade > 12)
      fail("INVALID_UNIT_LEVEL", "Learning level is invalid.", 400);
    await ensureRows(userId, characterId, role);
    await sql.begin(async tx => {
      const [account] = await tx<AccountRow[]>`select grade,grade_correct,completed_levels
        from app.unit_learning_accounts where user_id=${userId} for update`;
      if (!account) fail("UNIT_STATE_UNAVAILABLE", "Learning state is unavailable.", 503);
      if (account.grade === grade) return;
      await tx`update app.unit_learning_accounts set grade=${grade},grade_correct=0,
        source_difficulty=${difficultyForGrade(grade)},updated_at=now() where user_id=${userId}`;
      await tx`update app.user_profiles set difficulty=${difficultyForGrade(grade)}::app.difficulty_level,
        proficiency_source='selfReported'::app.proficiency_source,placement_score=null,
        placement_completed_at=null,version=version+1,updated_at=now() where user_id=${userId}`;
      await appendSyncChange(tx, { userId, commandId: randomUUID(),
        eventType: "unit_learning_level_changed", payload: { grade } });
    });
    return read(userId, characterId, role);
  }

  return { read, recordMessage, start, answer, changeGrade };
}
export type UnitLearningService = ReturnType<typeof createUnitLearningService>;
