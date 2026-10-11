import { z } from "zod";

/** 备考方向独立于基础英语水平；四级、六级仍沿用原有水平身份。 */
export const learningDirectionKeys = [
  "general",
  "entrance-english-1",
  "entrance-english-2",
  "toefl-ibt-2026",
  "ielts-academic",
] as const;
export const learningDirectionSchema = z.enum(learningDirectionKeys);
export type LearningDirection = z.infer<typeof learningDirectionSchema>;

export const learningDirections = [
  { id: "general", title: "通用英语", status: "available" },
  { id: "entrance-english-1", title: "考研英语一", status: "inReview" },
  { id: "entrance-english-2", title: "考研英语二", status: "inReview" },
  { id: "toefl-ibt-2026", title: "托福 iBT", status: "inReview" },
  { id: "ielts-academic", title: "雅思 Academic", status: "inReview" },
] as const satisfies readonly {
  id: LearningDirection;
  title: string;
  status: "available" | "inReview";
}[];
