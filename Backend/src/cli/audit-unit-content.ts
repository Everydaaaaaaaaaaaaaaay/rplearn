import { authoredUnitSeeds } from "../modules/learning/unit-seeds.js";

function normalized(value: string): string {
  return value.normalize("NFKC").trim().toLowerCase()
    .replace(/[.!?。！？，,\s]+/gu, " ").trim();
}

function appearsVerbatim(answer: string, material: string): boolean {
  const target = normalized(answer);
  return target.length > 0 && ` ${normalized(material)} `.includes(` ${target} `);
}

let copiedTotal = 0;
for (let grade = 1; grade <= 12; grade += 1) {
  const units = authoredUnitSeeds.filter(unit => unit.grade === grade);
  const copied = units.filter(unit => {
    const written = unit.questions.find(question => question.kind === "write");
    return written && appearsVerbatim(written.answer, unit.scene.map(beat => beat.english).join(" "));
  });
  copiedTotal += copied.length;
  console.log(`年级 ${String(grade)}: 短写答案可连续定位于英文剧情 ${String(copied.length)}/${String(units.length)}`);
  if (process.argv.includes("--ids"))
    for (const unit of copied) console.log(`  ${unit.id}`);
}
console.log(`合计：${String(copiedTotal)}/${String(authoredUnitSeeds.length)}`);
