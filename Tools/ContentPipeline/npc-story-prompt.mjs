export const npcStoryPrompt = `Write one original fictional character and their COMPLETE preauthored branching encounter in JSON.
This is a preauthored production library for an English-learning travel app, not live roleplay. No tool use.
The seed is a creative brief, not a real person's identity. Only age/gender constrain avatar compatibility.
NO image or appearance cues are supplied; never invent nationality/personality/job from appearance.
All briefs describe DIFFERENT people; preserve this one's niche, tensions and speech without making a caricature.
Write a rounded English character card matching this exact shape:
{"card":{"name":"seed name","age":0,"gender":"seed gender","regionId":"london","nationality":"fictional nationality chosen independently","occupation":"specific occupation","hobbies":["at least two"],"personality":"60-100 English words, strengths and contradictions","background":"100-150 English words, concrete past and current pursuit, no default tragedy","speechStyle":"distinct rhythm and habits","hometown":"place","languages":["English"],"birthday":"MM-DD","signature":"short line","appearance":"","personaVoice":{"values":["two"],"flaws":["two"],"boundaries":["two"],"conversationalHabits":["two"],"anchorLines":["three natural sample utterances"]}},"summaryZh":"80-140 Chinese characters about what makes them memorable","story":{"titleZh":"Chinese title","actionId":"seed actionId","nodes":[...]}}
Story is a complete binary tree of THREE parts. Nodes IN ORDER: start,a,b,aa,ab,ba,bb.
start has two choices leading to a,b. a has two choices to aa,ab; b has two choices to ba,bb.
The four terminal nodes have choices:[]. Each node is {"id":"...","beats":[{"speaker":"narrator or npc","english":"...","chinese":"..."}],"choices":[{"english":"...","chinese":"...","next":"..."}]}.
EVERY node: 4-6 beats, >=2 spoken NPC beats and >=1 narration. A beat is 1-2 natural sentences, 15-35 English words. Everyday B1 English, faithful natural Chinese translations.
Each played path thus has 12-18 beats, one developing shared experience, two genuine action decisions, a satisfying small ending.
The chosen starting ACTION must visibly occur in start. Explain how strangers begin talking without forced introductions or biographies.
Development follows ONLY its chosen action. Terminal aa/ab depend on a; ba/bb depend on b. Do not leak events from another branch.
Different choices change a concrete action/result, not just polite wording. All four endings must differ meaningfully and remember the path.
Characters retain agency and flaws, but never humiliate learners. Do not force user emotions, romance, possessions, expertise or past meetings.
Do not repeat whole beats. Avoid generic wisdom, biography dumping, instant intimacy and universal agreement.
Narration is observable action only, NEVER spoken quotations. Put ALL spoken words in npc beats. No English terms in Chinese translations unless a proper name requires them.
No exact time, morning/afternoon, season, daylight or cold/hot assumptions outside the supplied scene. Rain is allowed in rain cafe.
After EVERY terminal the UI will independently show Add Friend / Leave. Do not put contact gating, phone numbers or eligibility in content. Do not say already friends.
All story nodes have English and Chinese. Only JSON, no markdown. Keep planning short and spend output on complete content.`;
