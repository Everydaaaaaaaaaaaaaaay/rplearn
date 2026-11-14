// The reader and assembler use the same editorial projection of each candidate.
export function projectActivityStory(
  story,
  { originalCard, binding, placeTitleZh },
) {
  const projected = structuredClone(story);
  if (binding.preserveOriginalBackground)
    projected.background = originalCard.background;
  if (binding.migrationExplanationZh)
    projected.migrationExplanationZh = binding.migrationExplanationZh;

  projected.causality.reunionCommonFacts = `已有相遇记录确认用户此前见过${originalCard.name}。本次重逢位于${placeTitleZh}，地点属于当前情境。其余信息由本次可见状态和稳定人物设定提供，适用于新版四条初遇路径与旧活动联系人。`;

  const opening = projected.reunion.beats[0];
  opening.english = opening.english
    .replace(
      /^On (?:another|a later|a subsequent) (?:(?:winter|summer|weekend) )?(?:visit|outing) to /,
      "At ",
    )
    .replace(
      /^(?:On another|Another) (?:day|afternoon|morning|evening|weekend) (at|on|in) /,
      (_, preposition) =>
        preposition[0].toUpperCase() + preposition.slice(1) + " ",
    )
    .replace(
      /^Back (at|on|in) /,
      (_, preposition) =>
        preposition[0].toUpperCase() + preposition.slice(1) + " ",
    )
    .replace(/\bthe same /g, "the ");

  const chinese = opening.chinese.replace(
    /^(?:另一次|另一天|后来又一次|后来再|又一次)(?:来到|到)(.+?)(?:时)?，/u,
    "在$1，",
  );
  opening.chinese = chinese.replace(/^(?:另一次|另一天|再次)在/u, "在");
  return projected;
}
