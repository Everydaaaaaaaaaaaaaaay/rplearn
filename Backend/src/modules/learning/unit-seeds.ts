import { authoredUnitSeedsV3 } from "./unit-seeds-v3.js";

export type UnitQuestion = Readonly<{
  id: string;
  kind: "choice" | "order" | "write" | "multi";
  prompt: string;
  options: readonly string[];
  answer: string;
  acceptedAnswers?: readonly string[] | undefined;
  explanation: string;
}>;

export type UnitTemplate = Readonly<{
  id: string;
  roleKey: string;
  grade: number;
  title: string;
  objective: string;
  learningReference?: Readonly<{
    volumeId: string;
    unitNumber: number;
    evidenceUrl: string;
    designFocus: string;
    evidenceLevel: "sample-page" | "publisher-activity-index" | "official-lesson-index" | "curriculum-introduction";
  }>;
  scene: readonly Readonly<{ speaker: "narrator" | "character"; english: string; chinese: string }>[];
  questions: readonly UnitQuestion[];
}>;

export const authoredUnitSeeds: readonly UnitTemplate[] = authoredUnitSeedsV3;
