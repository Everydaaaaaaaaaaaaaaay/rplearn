import { describe, expect, it } from "vitest";
import { authoredUnitSeeds } from "../../../src/modules/learning/unit-seeds.js";
import { validateGeneratedUnit } from "../../../src/modules/learning/unit-generator.js";

function tokens(text: string): string[] {
  return (text.match(/[\p{L}\p{N}']+|[.!?]/gu) ?? []).map(value => value.toLowerCase()).sort();
}

describe("authored unit library", () => {
  it("covers every school year four times for each main character with checkable questions", () => {
    expect(authoredUnitSeeds).toHaveLength(144);
    expect(new Set(authoredUnitSeeds.map(unit => unit.id)).size).toBe(144);
    for (const role of ["oliver", "ruby", "marcus"])
      for (let grade = 1; grade <= 12; grade += 1) {
        const units = authoredUnitSeeds.filter(unit => unit.roleKey === role && unit.grade === grade);
        expect(units).toHaveLength(4);
        for (const unit of units) {
          expect(unit.scene.some(beat => beat.speaker === "character")).toBe(true);
          expect(unit.scene.every(beat => !beat.english.includes("{") && !beat.chinese.includes("{"))).toBe(true);
          if (grade <= 2) expect(unit.scene.every(beat => beat.english.split(/\s+/u).length <= 16)).toBe(true);
          expect(unit.questions.map(question => question.kind)).toEqual(["choice", "order", "write"]);
          for (const question of unit.questions) {
            if (question.kind === "choice") {
              expect(question.options).toHaveLength(3);
              expect(question.options.filter(option => option === question.answer)).toHaveLength(1);
            } else if (question.kind === "order") {
              expect(tokens(question.options.join(" "))).toEqual(tokens(question.answer));
            } else {
              expect(question.options).toHaveLength(0);
              expect(question.answer.length).toBeGreaterThan(1);
            }
          }
        }
      }
  });

  it("rejects generated choices with no unique answer", () => {
    const valid = {
      title: "A library sign", objective: "Read a simple sign", scene: [
        { speaker: "narrator", english: "You are standing near a library door.", chinese: "你站在图书馆门口。" },
        { speaker: "character", english: "The library is open today.", chinese: "图书馆今天开放。" },
      ],
      questions: [
        { id: "q1", kind: "choice", prompt: "图书馆今天怎样？", options: ["开放", "关闭", "搬走"], answer: "开放", explanation: "台词说今天开放。" },
        { id: "q2", kind: "order", prompt: "排成今天开放", options: ["open", "library", "is", "The", "."], answer: "The library is open.", explanation: "be 动词连接主语和状态。" },
        { id: "q3", kind: "write", prompt: "写出英语：开放的", options: [], answer: "open", explanation: "open 表示开放的。" },
      ],
    };
    expect(() => validateGeneratedUnit(valid, "oliver", 1)).not.toThrow();
    const ambiguous = { ...valid, questions: [{ ...valid.questions[0], options: ["开放", "开放", "关闭"] }, ...valid.questions.slice(1)] };
    expect(() => validateGeneratedUnit(ambiguous, "oliver", 1)).toThrow();
    const alreadyOrdered = { ...valid, questions: [valid.questions[0], { ...valid.questions[1], options: ["The", "library", "is", "open", "."] }, valid.questions[2]] };
    expect(() => validateGeneratedUnit(alreadyOrdered, "oliver", 1)).toThrow();
  });
});
