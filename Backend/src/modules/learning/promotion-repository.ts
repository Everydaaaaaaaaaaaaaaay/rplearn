import { randomUUID } from "node:crypto";
import type { TransactionSql } from "postgres";
import { AppError } from "../../shared/errors.js";
import { type LearningLevel } from "./content.js";
import type { LearningContextReader } from "./context.js";
import { learningPolicy, nextLearningLevel } from "./policy.js";
import {
  promotionCourseHash,
  promotionCourseSchema,
  type PromotionCourse,
} from "./promotion-content.js";

function fail(code: string, message: string): never {
  throw new AppError({ code, message, statusCode: 409 });
}
interface PromotionRow {
  id: string;
  from_level: LearningLevel;
  to_level: LearningLevel;
  course_hash: string;
  course: unknown;
  status: "started" | "completed" | "superseded";
  acknowledged_beats: number;
  revision: number;
  profile_version: number;
  completed_profile_version: number | null;
  completed_at: Date | string | null;
}
/** 调用者必须持有学习账号事务锁；档案写入由领域服务在同一事务内执行。 */
export class LearningPromotionSession {
  constructor(
    private readonly sql: TransactionSql,
    private readonly userId: string,
    private readonly context: LearningContextReader | undefined,
    private readonly courses: readonly PromotionCourse[],
  ) {}
  async eligibility(level: LearningLevel) {
    const course = this.courses.find((c) => c.level === level),
      nextLevel = nextLearningLevel(level);
    const [progress] = await this.sql<
      { points: number }[]
    >`select points from app.learning_level_progress where user_id=${this.userId} and level_key=${level}`;
    const [completed] = await this.sql<
      { id: string }[]
    >`select id from app.learning_promotions where user_id=${this.userId} and from_level=${level} and status='completed'`;
    const targetPoints = learningPolicy.pointsPerStar * learningPolicy.starsPerLevel,
      points = progress?.points ?? 0;
    const evidence = await this.sql<
      { goal_id: string; correct: number; units: number }[]
    >`
      select r.goal_id,count(distinct (a.unit_id,r.question_id))::int as correct,count(distinct a.unit_id)::int as units
      from app.learning_rewards r join app.learning_attempts a on a.id=r.attempt_id
      where r.user_id=${this.userId} and r.level_key=${level} and a.first_completed_at is not null
      group by r.goal_id`;
    const goals = (course?.requiredGoals ?? []).map((goal) => {
      const found = evidence.find((e) => e.goal_id === goal.id);
      return {
        ...goal,
        correct: found?.correct ?? 0,
        units: found?.units ?? 0,
        complete:
          (found?.correct ?? 0) >= goal.minimumCorrect &&
          (found?.units ?? 0) >= goal.minimumUnits,
      };
    });
    const [passed] = course
      ? await this.sql`
      select a.id from app.learning_attempts a
      join app.learning_unit_versions v on v.unit_id=a.unit_id and v.version=a.unit_version
      join jsonb_to_recordset(${JSON.stringify(course.transferUnits)}::jsonb) as wanted(id text,version integer,"contentHash" text)
        on wanted.id=a.unit_id and wanted.version=a.unit_version and wanted."contentHash"=v.content_hash
      where a.user_id=${this.userId} and a.level_key=${level} and a.first_completed_at is not null
        and (select count(*) from app.learning_rewards r where r.attempt_id=a.id)=jsonb_array_length(v.payload->'questions') limit 1`
      : [];
    const transferCompleted = Boolean(passed);
    const available = nextLevel
      ? await this.sql<
          { role_key: string; count: number }[]
        >`select role_key,count(*)::int as count from app.learning_units where published and level_key=${nextLevel} group by role_key`
      : [];
    const nextLevelContent = (course?.nextLevelRoles ?? []).map((roleKey) => ({
      roleKey,
      availableUnits: available.find((r) => r.role_key === roleKey)?.count ?? 0,
      requiredUnits: course?.minimumNextUnitsPerRole ?? 3,
    }));
    const blockers: { code: string; message: string }[] = [];
    if (!course)
      blockers.push({
        code: "course_unpublished",
        message: "本级完整课程与进阶标准尚在准备，现有学习进度会保留。",
      });
    if (points < targetPoints)
      blockers.push({
        code: "points_remaining",
        message: `还需积累 ${String(targetPoints - points)} 点，点亮本级九颗星。`,
      });
    if (goals.some((g) => !g.complete))
      blockers.push({
        code: "goals_remaining",
        message: "还有学习主题需要在不同单元中练习，详情见主题进度。",
      });
    if (course && !transferCompleted)
      blockers.push({
        code: "transfer_remaining",
        message: "请完成本级综合迁移单元；遗漏题目可以补答。",
      });
    if (!nextLevel)
      blockers.push({
        code: "highest_level",
        message: "已到当前课程的最高档位，可以继续练习。",
      });
    else if (course && nextLevelContent.some((r) => r.availableUnits < r.requiredUnits))
      blockers.push({
        code: "next_level_unavailable",
        message: "下一档的合格题库尚未准备完整，已获进度会保留。",
      });
    const [active] = await this.sql<
      { id: string }[]
    >`select id from app.learning_promotions where user_id=${this.userId} and from_level=${level} and status='started'`;
    return {
      level,
      nextLevel,
      points,
      targetPoints,
      goals,
      transferCompleted,
      nextLevelContent,
      courseVersion: course?.version ?? null,
      courseHash: course ? promotionCourseHash(course) : null,
      ready: blockers.length === 0 && !completed,
      completedPromotionId: completed?.id ?? null,
      activePromotionId: active?.id ?? null,
      blockers,
    };
  }
  private async profile() {
    if (!this.context?.promotionProfile)
      fail("LEARNING_PROMOTION_UNAVAILABLE", "进阶服务尚未就绪。");
    return this.context.promotionProfile(this.sql, this.userId);
  }
  async begin(level: LearningLevel) {
    const profile = await this.profile();
    if (profile.difficulty !== level)
      fail("LEARNING_LEVEL_CHANGED", "当前水平已改变，请重新打开英语旅程。");
    const [existing] = await this.sql<
      PromotionRow[]
    >`select * from app.learning_promotions where user_id=${this.userId} and from_level=${level} and status in ('started','completed')`;
    if (existing?.status === "completed") return this.snapshot(existing);
    const eligibility = await this.eligibility(level);
    if (!eligibility.ready)
      throw new AppError({
        code: "LEARNING_PROMOTION_NOT_READY",
        message: "尚未满足进阶条件。",
        statusCode: 409,
        details: eligibility,
      });
    const course = this.courses.find((c) => c.level === level);
    if (!course || !eligibility.nextLevel)
      fail("LEARNING_PROMOTION_NOT_READY", "本级进阶课程尚未发布。");
    if (existing?.course_hash === promotionCourseHash(course)) {
      if (existing.profile_version !== profile.version)
        await this
          .sql`update app.learning_promotions set profile_version=${profile.version},revision=revision+1 where id=${existing.id}`;
      return this.read(existing.id);
    }
    if (existing)
      await this
        .sql`update app.learning_promotions set status='superseded',revision=revision+1 where id=${existing.id}`;
    const id = randomUUID();
    await this
      .sql`insert into app.learning_promotions(id,user_id,from_level,to_level,course_hash,course,profile_version) values(${id},${this.userId},${level},${eligibility.nextLevel},${promotionCourseHash(course)},${JSON.stringify(course)}::jsonb,${profile.version})`;
    return this.read(id);
  }
  private async row(id: string) {
    const [row] = await this.sql<
      PromotionRow[]
    >`select * from app.learning_promotions where id=${id} and user_id=${this.userId}`;
    if (!row)
      throw new AppError({
        code: "LEARNING_PROMOTION_NOT_FOUND",
        message: "找不到这段进阶剧情。",
        statusCode: 404,
      });
    return row;
  }
  private snapshot(row: PromotionRow) {
    const course = promotionCourseSchema.parse(row.course);
    return {
      id: row.id,
      fromLevel: row.from_level,
      toLevel: row.to_level,
      status: row.status,
      story: course.story,
      courseHash: row.course_hash,
      acknowledgedBeats: row.acknowledged_beats,
      revision: row.revision,
      profileVersion: row.profile_version,
      completedProfileVersion: row.completed_profile_version,
      completedAt: row.completed_at ? new Date(row.completed_at).toISOString() : null,
    };
  }
  async read(id: string) {
    return this.snapshot(await this.row(id));
  }
  private assertCurrent(row: PromotionRow, revision: number) {
    if (row.status !== "started" || row.revision !== revision)
      fail("LEARNING_PROMOTION_CONFLICT", "这段剧情已更新，请刷新后继续。");
    const course = this.courses.find((c) => c.level === row.from_level);
    if (!course || promotionCourseHash(course) !== row.course_hash)
      fail(
        "LEARNING_PROMOTION_COURSE_CHANGED",
        "进阶课程已更新，请从英语旅程重新进入。",
      );
  }
  async advance(id: string, revision: number) {
    const row = await this.row(id);
    this.assertCurrent(row, revision);
    const course = promotionCourseSchema.parse(row.course);
    if (row.acknowledged_beats >= course.story.beats.length) return this.snapshot(row);
    await this
      .sql`update app.learning_promotions set acknowledged_beats=acknowledged_beats+1,revision=revision+1 where id=${id}`;
    return this.read(id);
  }
  async complete(
    id: string,
    revision: number,
    expectedProfileVersion: number,
    requestId: string,
  ) {
    const row = await this.row(id);
    // 不同请求重放完成只能查看既有成就，绝不把用户后来手选的水平改回去。
    if (row.status === "completed") return this.snapshot(row);
    this.assertCurrent(row, revision);
    const course = promotionCourseSchema.parse(row.course);
    if (row.acknowledged_beats !== course.story.beats.length)
      fail("LEARNING_PROMOTION_STORY_INCOMPLETE", "请先完成这段进阶剧情。");
    const profile = await this.profile();
    if (
      profile.difficulty !== row.from_level ||
      profile.version !== expectedProfileVersion ||
      row.profile_version !== expectedProfileVersion
    )
      fail(
        "LEARNING_LEVEL_CHANGED",
        "水平或个人档案已改变，请回到英语旅程重新确认进阶。",
      );
    if (!(await this.eligibility(row.from_level)).ready)
      fail(
        "LEARNING_PROMOTION_NOT_READY",
        "进阶条件或下一档课程供给已变化，请刷新英语旅程。",
      );
    if (!this.context?.promoteProfile)
      fail("LEARNING_PROMOTION_UNAVAILABLE", "档案进阶服务尚未就绪。");
    const updated = await this.context.promoteProfile(
      this.sql,
      this.userId,
      requestId,
      row.from_level,
      row.to_level,
      expectedProfileVersion,
    );
    await this
      .sql`update app.learning_promotions set status='completed',completed_at=now(),completed_profile_version=${updated.version},revision=revision+1 where id=${id}`;
    return this.read(id);
  }
}
