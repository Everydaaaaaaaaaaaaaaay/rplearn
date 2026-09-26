import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { z } from "zod";
import { contentHash, levelSchema } from "./content.js";
import { loadCuratedCatalog } from "./catalog.js";
import { nextLearningLevel } from "./policy.js";

const id = z.string().regex(/^[a-z][a-z0-9_.-]{0,119}$/);
const text = z.string().trim().min(1).max(1000);
/** 课程验收单与题库分开发布；不能用几份样板自动推断整个学年的完成标准。 */
export const promotionCourseSchema = z
  .strictObject({
    level: levelSchema,
    version: z.number().int().positive(),
    requiredGoals: z
      .array(
        z.strictObject({
          id,
          title: text.max(100),
          minimumCorrect: z.number().int().min(1).max(100),
          minimumUnits: z.number().int().min(2).max(30),
        }),
      )
      .min(1)
      .max(100),
    transferUnits: z
      .array(
        z.strictObject({
          id,
          version: z.number().int().positive(),
          contentHash: z.string().regex(/^[a-f0-9]{64}$/),
        }),
      )
      .min(1)
      .max(50),
    nextLevelRoles: z.array(id).min(1).max(20),
    minimumNextUnitsPerRole: z.number().int().min(3).max(100),
    story: z.strictObject({
      id,
      title: text.max(100),
      beats: z
        .array(
          z.strictObject({
            id,
            speaker: text.max(60),
            text: text.max(500),
            translation: text.max(500),
          }),
        )
        .min(2)
        .max(12),
    }),
    review: z.strictObject({
      reviewer: text.max(100),
      reviewedAt: z.iso.date(),
      notes: text.min(30),
      sourceIds: z.array(id).min(1).max(20),
    }),
  })
  .superRefine((course, context) => {
    for (const values of [
      course.requiredGoals.map((g) => g.id),
      course.transferUnits.map((u) => u.id),
      course.nextLevelRoles,
      course.story.beats.map((b) => b.id),
    ]) {
      if (new Set(values).size !== values.length)
        context.addIssue({
          code: "custom",
          message: "进阶课程的目标、迁移单元、角色或镜头标识不能重复。",
        });
    }
    if (!nextLearningLevel(course.level))
      context.addIssue({ code: "custom", message: "最高档位不能配置继续升级。" });
  });
export type PromotionCourse = z.infer<typeof promotionCourseSchema>;
export const promotionCourseHash = (course: PromotionCourse) => contentHash(course);
export async function loadPromotionCourses(
  directory: string,
): Promise<readonly PromotionCourse[]> {
  const manifest = z
    .strictObject({
      version: z.literal(1),
      courses: z.array(promotionCourseSchema).max(15),
    })
    .parse(
      JSON.parse(await readFile(join(directory, "promotions.json"), "utf8")) as unknown,
    );
  if (new Set(manifest.courses.map((c) => c.level)).size !== manifest.courses.length)
    throw new Error("同一水平不能同时发布两份进阶课程。");
  const catalog = await loadCuratedCatalog(directory);
  for (const course of manifest.courses) {
    for (const goal of course.requiredGoals)
      if (
        !catalog.registry.goals.some(
          (g) => g.id === goal.id && g.level === course.level,
        )
      )
        throw new Error("进阶目标缺少对应水平的已核读课程依据。");
    for (const source of course.review.sourceIds)
      if (!catalog.registry.sources.some((s) => s.id === source))
        throw new Error("进阶课程引用了未登记来源。");
    for (const ref of course.transferUnits) {
      const unit = catalog.units.find(
        (u) => u.id === ref.id && u.version === ref.version && u.level === course.level,
      );
      if (!unit || contentHash(unit) !== ref.contentHash)
        throw new Error("综合迁移单元的版本或审核指纹不一致。");
    }
  }
  return manifest.courses;
}
