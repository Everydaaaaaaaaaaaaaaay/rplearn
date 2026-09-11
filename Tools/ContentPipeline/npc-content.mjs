const nodeIds = ['start', 'a', 'b', 'aa', 'ab', 'ba', 'bb'];

export function validate(value, seed) {
  const errors = [];
  const card = value?.card;
  if (!card || card.name !== seed.name || card.age !== seed.age || card.gender !== seed.gender || card.regionId !== seed.regionId) errors.push('Character identity must exactly match seed');
  for (const field of ['occupation', 'personality', 'background', 'speechStyle', 'nationality', 'hometown']) if (typeof card?.[field] !== 'string' || !card[field].trim()) errors.push('Missing card.' + field);
  for (const field of ['values', 'flaws', 'boundaries', 'conversationalHabits', 'anchorLines']) if (!Array.isArray(card?.personaVoice?.[field]) || card.personaVoice[field].length < 2) errors.push('Missing personaVoice.' + field);
  if (!Array.isArray(card?.hobbies) || card.hobbies.length < 2 || !card?.languages?.includes('English')) errors.push('Missing hobbies or English language');
  if (typeof value?.summaryZh !== 'string' || !value.summaryZh.trim()) errors.push('Missing summaryZh');
  const story = value?.story;
  if (!story?.titleZh || story?.actionId !== seed.actionId || !Array.isArray(story?.nodes) || story.nodes.length !== 7) errors.push('Story needs exactly seven nodes for the assigned action');
  const nodes = new Map((story?.nodes ?? []).map(n => [n.id, n]));
  if (nodes.size !== 7 || nodeIds.some(id => !nodes.has(id))) errors.push('Wrong/duplicate node IDs');
  for (const id of nodeIds) {
    const node = nodes.get(id);
    const children = id === 'start' ? ['a', 'b'] : ['a', 'b'].includes(id) ? [id + 'a', id + 'b'] : [];
    if (!node || !Array.isArray(node.beats) || node.beats.length < 4 || node.beats.length > 6) { errors.push(id + ' requires 4-6 beats'); continue; }
    if (node.beats.filter(b => b.speaker === 'npc').length < 2 || !node.beats.some(b => b.speaker === 'narrator')) errors.push(id + ' needs >=2 NPC beats and narration');
    for (const beat of node.beats) {
      if (!['npc', 'narrator'].includes(beat.speaker) || typeof beat.english !== 'string' || !beat.english.trim() || typeof beat.chinese !== 'string' || !beat.chinese.trim() || beat.english.length > 500 || beat.chinese.length > 300) errors.push(id + ' invalid beat');
    }
    if (!Array.isArray(node.choices) || node.choices.length !== children.length || children.some((child, i) => node.choices[i]?.next !== child)) errors.push(id + ' invalid branch edges');
    for (const choice of node.choices ?? []) if (!choice.english?.trim() || !choice.chinese?.trim()) errors.push(id + ' missing choice text');
  }
  return errors;
}
