import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createLibraryProvider } from "./library-provider.mjs";
import { projectActivityStory } from "./activity-world-editorial.mjs";

// Offline content authoring only. No database imports, credentials or activation.
const [phase, inputPath, output] = process.argv.slice(2);
if (
  !["prepare", "stories", "review", "diversity", "repair", "patch"].includes(
    phase,
  ) ||
  !inputPath ||
  !output
) {
  throw Error(
    "Usage: activity-world-author.mjs prepare world.json private-output; or stories|review|diversity|repair|patch input.json private-output",
  );
}
const input = JSON.parse(readFileSync(inputPath, "utf8"));
mkdirSync(output, { recursive: true });
if (phase === "prepare") {
  const read = (path) => JSON.parse(readFileSync(path, "utf8"));
  const bindings = read(
    join(dirname(inputPath), "assignments.json"),
  ).characters;
  const moves = read(
    join(dirname(inputPath), "geography-decisions.json"),
  ).moves;
  const repo = fileURLToPath(new URL("../../", import.meta.url));
  const photos = read(
    join(repo, "Assets/Activities/CityPlaces-v2/selected-photos.json"),
  ).photos;
  const prepared = {
    cities: input.cities,
    places: input.places.map((place) => {
      const photo = photos.find((photo) => photo.placeId === place.id);
      if (!photo || photo.cityId !== place.cityId)
        throw Error("Missing exact-place photo " + place.id);
      return {
        id: place.id,
        cityId: place.cityId,
        titleZh: place.titleZh,
        category: place.category,
        populationTarget: place.populationTarget,
        spaceFacts: place.spaceFacts,
        photoSpatialNotes: photo.spatialNotes ?? "",
        photoTitle: photo.fileTitle ?? "",
      };
    }),
    characters: input.characters.map((person) => {
      const binding = bindings.find((binding) => binding.npcId === person.id);
      if (!binding) throw Error("Missing fixed binding " + person.id);
      const move = moves.find((move) => move.name === person.originalCard.name);
      const prepared = {
        id: person.id,
        originalCard: person.originalCard,
        currentCityId: binding.cityId,
        geographyInstruction:
          move?.reason ??
          "Preserve existing city, childhood and residence history.",
      };
      if (binding.lockedStoryId) {
        prepared.lockedStory = {
          assignment: person.assignment,
          story: input.stories.find(
            (story) => story.id === binding.lockedStoryId,
          ),
        };
      }
      return prepared;
    }),
    bindings,
  };
  writeFileSync(
    join(output, "input.json"),
    JSON.stringify(prepared, null, 2) + "\n",
  );
  console.log(
    JSON.stringify({
      characters: prepared.characters.length,
      places: prepared.places.length,
      prepared: true,
    }),
  );
  process.exit(0);
}
const objectSchema = (properties) => ({
  type: "object",
  properties,
  required: Object.keys(properties),
  additionalProperties: false,
});
const textSchema = { type: "string", minLength: 1, maxLength: 4000 };
const bilingualSchema = objectSchema({
  english: { type: "string", minLength: 1, maxLength: 420 },
  chinese: { type: "string", minLength: 1, maxLength: 260 },
});
const choiceSchema = objectSchema({
  english: { type: "string", minLength: 1, maxLength: 180 },
  chinese: { type: "string", minLength: 1, maxLength: 100 },
});
const fourBeats = {
  scene: bilingualSchema,
  line1: bilingualSchema,
  action: bilingualSchema,
  line2: bilingualSchema,
};
const storySchema = objectSchema({
  titleZh: { type: "string", minLength: 1, maxLength: 80 },
  scenes: objectSchema(
    Object.fromEntries(
      ["start", "a", "b", "aa", "ab", "ba", "bb"].map((id) => [
        id,
        objectSchema(
          ["start", "a", "b"].includes(id)
            ? {
                ...fourBeats,
                firstChoice: choiceSchema,
                secondChoice: choiceSchema,
              }
            : fourBeats,
        ),
      ]),
    ),
  ),
  reunion: objectSchema({
    titleZh: { type: "string", minLength: 1, maxLength: 80 },
    ...fourBeats,
  }),
  causality: objectSchema(
    Object.fromEntries(
      [
        "presenceReason",
        "placeAttitude",
        "stayingConstraint",
        "currentGoal",
        "currentState",
        "contactTrigger",
        "characterContinuity",
        "reactionAndChange",
        "spatialContinuity",
        "reunionCommonFacts",
      ].map((key) => [key, textSchema]),
    ),
  ),
  background: textSchema,
  migrationExplanationZh: textSchema,
  fit: { type: "string", enum: ["natural", "conditional"] },
  fitEvidence: textSchema,
});
const reviewSchema = objectSchema({
  npcId: textSchema,
  verdict: { type: "string", enum: ["pass", "revise"] },
  issues: {
    type: "array",
    items: objectSchema({
      severity: { type: "string", enum: ["major", "minor"] },
      node: textSchema,
      quote: textSchema,
      reason: textSchema,
      repair: textSchema,
    }),
  },
  strengths: { type: "array", items: textSchema },
  endings: objectSchema({
    aa: textSchema,
    ab: textSchema,
    ba: textSchema,
    bb: textSchema,
  }),
  reunionEvidence: textSchema,
});
const nullableSchema = (schema) => ({ anyOf: [schema, { type: "null" }] });
const patchSchema = objectSchema({
  titleZh: nullableSchema(storySchema.properties.titleZh),
  scenes: objectSchema(
    Object.fromEntries(
      Object.entries(storySchema.properties.scenes.properties).map(
        ([id, schema]) => [id, nullableSchema(schema)],
      ),
    ),
  ),
  reunion: nullableSchema(storySchema.properties.reunion),
  causality: storySchema.properties.causality,
  background: nullableSchema(textSchema),
  migrationExplanationZh: nullableSchema(textSchema),
  fit: nullableSchema(storySchema.properties.fit),
  fitEvidence: nullableSchema(textSchema),
});
const diversitySchema = objectSchema({
  cityId: textSchema,
  overview: textSchema,
  fixes: {
    type: "array",
    items: objectSchema({
      npcId: textSchema,
      dimension: textSchema,
      reason: textSchema,
      brief: textSchema,
    }),
  },
  keepNpcIds: { type: "array", items: textSchema },
});
const writing = ["stories", "repair", "patch"].includes(phase);
const provider = createLibraryProvider(output, {
  providerName: "openai",
  model: writing || phase === "diversity" ? "gpt-6.1-sol" : "gpt-5.4-mini",
  reasoningEffort: phase === "review" ? "low" : "medium",
  promptPriceCeiling: writing || phase === "diversity" ? 2 : 0.75,
  completionPriceCeiling: writing || phase === "diversity" ? 10 : 4.5,
  responseSchema:
    phase === "patch"
      ? patchSchema
      : writing
        ? storySchema
        : phase === "diversity"
          ? diversitySchema
          : reviewSchema,
  timeoutMs: 600000,
  capCNY: input.authoringCapCNY ?? 200,
});
const read = (path) => JSON.parse(readFileSync(path, "utf8"));
const save = (path, value) =>
  writeFileSync(path, JSON.stringify(value, null, 2) + "\n");

const principles = `You are writing LingoTrip's fixed first encounters for adult English learners.
The player only chose a destination. They have no assigned job, spending, purchase, language skill,
relationship, backstory or reason for being there. Let choices determine their involvement.
Preserve the original character's core identity, occupation, personality, interests, values, flaws,
boundaries and distinctive speech. Never infer citizenship or temperament from name or appearance.
Place attendance can be pleasure, obligation, inconvenience, work, a mundane errand, or a compromise.
Distinguish enduring temperament from today's energy, intention, trust and willingness to talk.
A quiet person can initiate for a concrete reason. An outgoing person can be distracted or guarded.
Most ordinary contact is civil. Do not turn boundaries into contempt, threats or unearned hostility.
Warmth, playfulness, curiosity and generosity are welcome when this person's card supports them.
Do not make every quiet choice receive a cold dismissal. No stranger needs to earn basic courtesy.
Do not turn everyone into a helper, guide, teacher, wise craftsperson or an instantly intimate friend.
Keep imperfections visible without making the user a therapist. Conversation need not heal anyone.
No unearned intimacy, public confessions on demand, secret gifts, obligatory contact exchange,
scores, friendship rewards, generic 'comfortable silence' endings or moralizing narrator summaries.
Write ordinary spoken English, clear Chinese translations and concrete actions.
No slogans, philosophical lessons, decorative metaphors, semicolons or explanatory colons.
Avoid 'not X but Y' framing. Natural disagreement can happen through specific replies.
All physical action must fit supplied photograph facts and public access.
Do not invent a staircase, accessible upper gallery, shop, bench, pier, exhibit, event or facility
to solve a plot. Temporary carried objects are allowed with a reason. Use the photographed area.
No walking out into a new scene to reach a climax. No dangerous behavior or blocked traffic.
Public space and commerce rules apply. Employees, patrons and passers-by keep their own agency.
No claims about actual current prices, timetables, opening hours or permissions.
Old park/pond/rain incident details are legacy first-meeting content, not a mandatory new premise.
Keep meaningful past biography. Remove deictic old 'today in this park' wording from the new card.
Return JSON only.`;

const storyPrompt =
  principles +
  `
Write ONE complete bilingual fixed first encounter and short reunion for the locked binding.
Return {titleZh,scenes,reunion,causality,background,migrationExplanationZh,fit,fitEvidence}.
Keep the job but avoid a job interview, craft lesson or asking a stranger to judge professional work.
The ordinary interaction should reveal a specific flaw or boundary through behavior, not explain it.
Give the person a reason to be here BEFORE the user arrives. Establish a concrete two-person trigger.
The opening must make sense without assuming the player already asked a question or complimented them.
Avoid soliciting volunteer labor or professional judgment from strangers as the default contact.
Choices should lead to different actions or understandings. A boundary can stay intact in a warm scene.
The flaw need not appear in every node. Repeated anchor lines do not substitute for character voice.
Use narrator fields for stage directions. NPC line fields contain ONLY what the NPC says, no quotes.
No repeating anchor lines verbatim. A joke requires an actual joke before anyone rates it.
Use only supplied spatial facts. No new bridge approach, stairs, bench, ticket office or counter.
A carried object can exist for a reason. Do not invent public fixtures to make a plot work.
The player's actions and utterances come ONLY from selected choices. Avoid personal questions
that assume their age, career, phone ownership, spending, romantic availability or free time.
Follow an authorBrief if supplied. Otherwise create an ordinary scene-specific interaction.
Make the four outcomes physically or socially different. End the immediate encounter in each.
A refusal does not need to be rewarded with a life lesson. No therapist, guide or tutor role.

FORMAT IS EXACT. scenes is an OBJECT with SEVEN keys start,a,b,aa,ab,ba,bb.
Each scene has exactly FOUR bilingual content fields named scene,line1,action,line2.
Each content field is {english,chinese}. scene and action are narration. line1 and line2 are NPC speech.
Each English field <=420 characters, Chinese <=260. Keep English mostly 1-2 short sentences.
Narration first, then NPC speech, then concrete narration, then NPC speech. No extra beats or arrays.
start/a/b additionally have firstChoice and secondChoice, each {english,chinese}.
These are USER utterances/actions, English <=180 characters, Chinese <=100.
The engine connects start choices to a/b, a to aa/ab, b to ba/bb.
aa/ab/ba/bb are ENDINGS. No choices, questions for a reply or promised continuation in them.
Put the actual consequence into their four fields. All paths have exactly three scenes.
Name and place must be known in start. Do not assume the user supplies their own name.

reunion is {titleZh,scene,line1,action,line2}, with four bilingual fields exactly as above.
It is a later outing at the same place. Recognition plus a new small current situation is enough.
It MUST ALSO work if the user met this NPC in the OLD park/pond/rain story.
Never mention an earlier new-scene event, object, profession discussion, answer, user name,
shared agreement or preference. Never say 'last time', 'still doing X' or 'you were the one who'.
Don't simply repeat the first incident or assume the user joins an activity on reunion.

causality has exactly presenceReason,placeAttitude,stayingConstraint,currentGoal,currentState,
contactTrigger,characterContinuity,reactionAndChange,spatialContinuity,reunionCommonFacts.
Use concise concrete Chinese describing the actual story. reactionAndChange names all four outcomes.
background is an English biography retaining meaningful original facts, removing legacy 'today'
scene setup and applying binding.geographyInstruction. Core personality/occupation/interests stay.
Do not fabricate childhood or citizenship. migrationExplanationZh describes exact revisions.
fit is natural or conditional. fitEvidence is concise Chinese. No other output keys. JSON only.
`;

const reviewPrompt = `You are an exacting bilingual fiction continuity editor for LingoTrip.
Compare the archived original card, approved geographic binding, photo spatial facts and EVERY full path.
Protected core fields are name,age,gender,appearance,occupation,personality,hobbies,personaVoice.
Nationality and hometown are editable only under the explicit binding.geographyInstruction.
Nine explicitly fictional London nationalities/hometowns were authorized editorial corrections
into British/real London locations. Do NOT ask to restore fictional countries or fictional towns.
Sixteen current-city changes were explicitly planned. Preserve their real earlier experiences.
IMPORTANT localConnection is CITY/METRO-LEVEL, never the individual place or neighborhood.
A Queens childhood supports grew_up_here for NEW YORK CITY, not specifically Washington Square.
Bukit Merah and Jurong childhoods support Singapore. Mount Roskill supports Auckland.
The three allowed values are grew_up_here,settled_here,temporary_stay. Do not propose new enum values.
If geographyInstruction explicitly authorizes a correction, assess fidelity to that instruction.
This is a content review, not a syntax check. Report concrete defects with node IDs and quoted text.
Check scene necessity, believable attendance/contact, agency, enduring character vs current state,
original occupation/flaws/boundaries, no forced improvement, real citizenship and existing childhood,
four causally distinct endings, choice responses, prop/location/time continuity, natural bilingual
equivalence, public access and no invented facilities. No made-up world knowledge or current prices.
Check no assumed user purchase/job/backstory, no obligatory friendship, no private disclosure on demand.
Compare the updated biography with meaningful original life facts and relationships. Geographic
editorial corrections and removal of old deictic scene setup are allowed. Do not invent citizenship
or erase a real childhood move to meet a local quota. Check localConnection against the biography.
Check causal metadata against the actual text, including reunionCommonFacts. A description claiming
the old user first met this person at the new place is a defect even if the reunion itself is neutral.
Reunion MUST work for old users who met this NPC at a different legacy scene and for all four paths.
Schema requires >=2 NPC lines per node, but avoid padding them with repeated generic reassurance.
Return {npcId,verdict:'pass'|'revise',issues:[{severity:'major'|'minor',node,quote,reason,repair}],
strengths:[short concrete evidence],endings:{aa,ab,ba,bb},reunionEvidence}.
A 'pass' needs no major issues. Minor language roughness may remain. Be critical and specific.
Read quoted dialogue in its actual narrative frame. A clearly introduced published letter or
fictional performance has its own recipient; its words do not assign family or history to the player.
An explicitly addressed third party can have a cousin or sibling without assigning one to the player.
A reunion is a later encounter and can have its own goal, mood or match result. Initial-encounter
causality does not freeze the NPC's future days. Only shared player history must fit every path.
Preserve pronouns actually used in the original card, including when gender is 'other'. Do not
infer a required pronoun change from a gender label alone.
Do not approve simply because the supplied author claims consistency. Chinese analysis. JSON only.`;

const diversityPrompt = `Review one whole city's fixed NPC encounters for narrative sameness.
The supplied characters have immutable identities and one locked place each. Keep those bindings.
Compare actual contactTrigger and opening scenes, not job labels. Four different jobs can still
produce four identical 'bag bumps you / move bag off seat / dropped paper' introductions.
Also compare reunions city-wide. Repeated minor mishaps with reversed clothes, tangled sleeves,
backwards shopping lists, duplicate books or silly mistakes make distinct people feel identical.
Compare energy, motives, trust and the actual interaction. Flaws need not appear on every visit.
Replacing a dropped receipt with a dropped label or a book edge sticking into the aisle is STILL
an accidental physical intrusion. Replacing reversed clothes with tangled sleeves or a torn page
is STILL a minor mishap. Propose genuinely different contact mechanisms and current states.
Possible ordinary triggers include a bounded factual question, a shared visible occurrence,
clarifying a remark, or a normal negotiation of public space. Don't make all replacements questions
or experts offering help. Quiet people can have a concrete reason to speak. Sociable people can be busy.
Reunions have FOUR beats and NO choices/branches. Do not propose branching reunions.
For each genuine cluster, retain the most character-specific case and propose focused repairs
for selected others. Warmth, low energy, obligation, distraction, delight, polite distance and mild
friction can all occur. Do not turn everyone guarded or make everyone eager to teach or help.
Propose concrete replacement contact and/or reunion premises, appropriate to THIS person's
original card and exact photo space, which the writer can implement with four distinct endings.
A character can dislike or tolerate the place. Professional skill need not drive every conversation.
No new permanent traits, geography, facilities, public events, work lectures or assumed user actions.
Reunion needs no remembered new-story event and must work for legacy contacts. Greeting plus
a specific new current situation is enough. Vary it beyond humorous mistakes and self-deprecation.
Keep each person's current plot when possible. A focused new opening can retain its branch logic.
Return {cityId,overview,fixes:[{npcId,dimension,reason,brief}],keepNpcIds}.
dimension names the actual overlap. reason quotes the existing repeated mechanism. brief gives
one concrete replacement, not 'make it more diverse'. Preserve useful existing differences.
Every referenced npcId MUST be copied exactly from the supplied city. Chinese. JSON only.`;

const patchPrompt =
  principles +
  `
Apply the supplied editorial repairBrief to the complete previous draft. Preserve all unaffected
wording, biography and branch outcomes. Repair every downstream reference affected by a new trigger.
The seven scene keys start,a,b,aa,ab,ba,bb are REQUIRED. Set each UNCHANGED scene to null.
A changed scene uses four bilingual fields scene,line1,action,line2, and firstChoice/secondChoice
for start/a/b only, exactly like the authoring contract. Narration and NPC speech alternate.
The engine controls all graph edges. Read the actual selected parent choice on every path.
Set reunion to null unless it needs repair. A changed reunion is titleZh plus four bilingual fields,
with NO choices. It must work for old park/pond/rain contacts and every first-meeting branch.
Minor mishaps are not the default reunion. Follow the concrete variation in repairBrief.
Return complete, accurate Chinese causality for the repaired story. Set other unchanged metadata
fields to null. If binding.preserveOriginalBackground is true, set background to null.
Use narrator fields for actions, NPC line fields only for actual speech. No actor directions in speech.
Avoid a new job lesson or unsolicited judgment task. Keep the person's own reason for attending,
social energy, trust, flaws and choices distinct. Courtesy does not erase a boundary or imperfection.
No new permanent traits, invented facilities, off-scene climax or assumed user job/purchases/family.
Apply explicitly authorized geographic instructions. Keep original real childhoods and relationships.
The updated first meeting remains bound to the exact place. JSON only.`;

function compileStory(raw) {
  const edges = {
    start: ["a", "b"],
    a: ["aa", "ab"],
    b: ["ba", "bb"],
    aa: [],
    ab: [],
    ba: [],
    bb: [],
  };
  const content = (block) =>
    ["scene", "line1", "action", "line2"].map((field, index) => {
      const beat = block?.[field];
      if (
        typeof beat?.english !== "string" ||
        typeof beat?.chinese !== "string"
      )
        throw Error("Missing bilingual field " + field);
      if (
        !beat.english.trim() ||
        !beat.chinese.trim() ||
        beat.english.length > 420 ||
        beat.chinese.length > 260
      )
        throw Error("Beat length outside runtime contract");
      return {
        speaker: index % 2 === 0 ? "narrator" : "npc",
        english: beat.english,
        chinese: beat.chinese,
      };
    });
  const nodes = Object.entries(edges).map(([id, destinations]) => {
    const block = raw.scenes?.[id];
    const choices = destinations.map((next, index) => {
      const choice = block?.[index === 0 ? "firstChoice" : "secondChoice"];
      if (
        typeof choice?.english !== "string" ||
        typeof choice?.chinese !== "string"
      )
        throw Error("Missing choice at " + id);
      if (
        !choice.english.trim() ||
        !choice.chinese.trim() ||
        choice.english.length > 180 ||
        choice.chinese.length > 100
      )
        throw Error("Choice length outside runtime contract");
      return { english: choice.english, chinese: choice.chinese, next };
    });
    return { id, beats: content(block), choices };
  });
  const { scenes, reunion, ...metadata } = raw;
  return {
    ...metadata,
    nodes,
    reunion: { titleZh: reunion.titleZh, beats: content(reunion) },
  };
}

function compilePatch(raw, previous) {
  const named = (item) => {
    if (
      item.beats.length !== 4 ||
      item.beats.some(
        (beat, index) =>
          beat.speaker !== (index % 2 === 0 ? "narrator" : "npc"),
      )
    ) {
      throw Error("Patch requires the existing four-beat authoring layout");
    }
    const fields = Object.fromEntries(
      ["scene", "line1", "action", "line2"].map((field, index) => [
        field,
        {
          english: item.beats[index].english,
          chinese: item.beats[index].chinese,
        },
      ]),
    );
    for (const [index, choice] of (item.choices ?? []).entries()) {
      fields[index === 0 ? "firstChoice" : "secondChoice"] = {
        english: choice.english,
        chinese: choice.chinese,
      };
    }
    return fields;
  };
  const metadata = Object.fromEntries(
    Object.entries(raw).filter(
      ([key, value]) => !["scenes", "reunion"].includes(key) && value !== null,
    ),
  );
  return compileStory({
    ...previous,
    ...metadata,
    scenes: Object.fromEntries(
      previous.nodes.map((node) => [
        node.id,
        raw.scenes[node.id] ?? named(node),
      ]),
    ),
    reunion: raw.reunion ?? {
      titleZh: previous.reunion.titleZh,
      ...named(previous.reunion),
    },
  });
}

async function requestResult(key, prompt, data, tokenLimit) {
  const path = join(output, key + ".result.json");
  const raw = await provider.request(key, prompt, data, tokenLimit);
  if (existsSync(path)) return read(path);
  const result =
    phase === "patch"
      ? compilePatch(raw, data.story)
      : writing
        ? compileStory(raw)
        : raw;
  if (phase === "review" && result.npcId !== data.person.id)
    throw Error("Reviewer returned the wrong person");
  if (phase === "diversity") {
    const allowed = new Set(data.people.map((person) => person.binding.npcId));
    if (
      result.cityId !== data.city.id ||
      result.fixes.some((fix) => !allowed.has(fix.npcId)) ||
      result.keepNpcIds.some((id) => !allowed.has(id))
    ) {
      throw Error("Diversity review changed the roster");
    }
  }
  save(path, result);
  return result;
}

const revisionsPath = join(output, "revisions.json");
const revisions = existsSync(revisionsPath) ? read(revisionsPath) : {};
const readStory = (binding) => {
  const person = input.characters.find((person) => person.id === binding.npcId);
  const story = revisions[binding.npcId]
    ? read(join(output, revisions[binding.npcId] + ".result.json"))
    : binding.lockedStoryId
      ? person.lockedStory.story
      : read(join(output, "first-v10-" + binding.npcId + ".result.json"));
  return projectActivityStory(story, {
    originalCard: person.originalCard,
    binding,
    placeTitleZh: input.places.find((place) => place.id === binding.placeId)
      .titleZh,
  });
};
let jobs;
if (phase === "diversity") {
  jobs = input.cities.map((city) => ({
    key: "diversity-v" + (input.reviewRound ?? 1) + "-" + city.id,
    data: {
      city,
      places: input.places.filter((place) => place.cityId === city.id),
      people: input.bindings
        .filter((binding) => binding.cityId === city.id)
        .map((binding) => {
          const card = input.characters.find(
            (person) => person.id === binding.npcId,
          ).originalCard;
          const story = readStory(binding);
          return {
            binding,
            card: {
              name: card.name,
              age: card.age,
              occupation: card.occupation,
              hobbies: card.hobbies,
              personality: card.personality,
              personaVoice: card.personaVoice,
            },
            causality: story.causality,
            start: story.nodes.find((node) => node.id === "start"),
            reunion: story.reunion,
          };
        }),
    },
  }));
} else {
  jobs = input.bindings
    .filter(
      (binding) =>
        (!input.selectedIds || input.selectedIds.includes(binding.npcId)) &&
        (phase === "review" || !binding.lockedStoryId) &&
        (!["repair", "patch"].includes(phase) ||
          input.repairs?.some((repair) => repair.npcId === binding.npcId)),
    )
    .map((binding) => {
      const person = input.characters.find((c) => c.id === binding.npcId);
      if (!person || binding.cityId !== person.currentCityId)
        throw Error("Unknown or cross-city binding");
      const place = input.places.find((p) => p.id === binding.placeId);
      if (!place || place.cityId !== binding.cityId)
        throw Error("Unknown or cross-city place");
      const neighbors = input.bindings
        .filter(
          (b) => b.placeId === binding.placeId && b.npcId !== binding.npcId,
        )
        .map(
          (b) => input.characters.find((c) => c.id === b.npcId)?.originalCard,
        );
      const key =
        (phase === "stories"
          ? "first-v" + (input.generationRound ?? 10) + "-"
          : ["repair", "patch"].includes(phase)
            ? phase + "-v" + (input.repairRound ?? 1) + "-"
            : "editor-v" + (input.reviewRound ?? 10) + "-") + person.id;
      const data = {
        person,
        place,
        binding,
        ...(phase === "stories" ? { neighbors } : {}),
      };
      if (phase !== "stories") {
        const replayingRepair =
          ["repair", "patch"].includes(phase) && revisions[person.id] === key;
        // Replaying a completed repair must use its original candidate. The
        // provider still checks the entire request hash before reusing a receipt.
        data.story = replayingRepair
          ? JSON.parse(read(join(output, key + ".request.json")).input).story
          : readStory(binding);
      }
      if (["repair", "patch"].includes(phase)) {
        data.repairBrief = input.repairs.find(
          (repair) => repair.npcId === binding.npcId,
        );
      }
      return { key, data, npcId: person.id };
    });
}
const failures = [];
let next = 0;
async function worker() {
  while (next < jobs.length) {
    const job = jobs[next++];
    try {
      const prompt =
        phase === "patch"
          ? patchPrompt
          : phase === "repair"
            ? storyPrompt +
              "\nRepair the supplied draft using repairBrief. Preserve unaffected biography, plot and character-specific voice. Apply all concrete review issues. Update causal evidence to match the repaired text. Return the entire named-field story contract."
            : phase === "stories"
              ? storyPrompt
              : phase === "diversity"
                ? diversityPrompt
                : reviewPrompt;
      await requestResult(
        job.key,
        prompt,
        job.data,
        writing ? 12000 : phase === "diversity" ? 10000 : 6000,
      );
      if (["repair", "patch"].includes(phase)) revisions[job.npcId] = job.key;
      console.log(
        JSON.stringify({
          done: job.key,
          accountedCNY: +provider.accountedCNY().toFixed(4),
        }),
      );
    } catch (error) {
      failures.push({ key: job.key, error: error.message });
      console.log(JSON.stringify({ failed: job.key, error: error.message }));
    }
  }
}
await Promise.all(Array.from({ length: 12 }, worker));
if (["repair", "patch"].includes(phase)) save(revisionsPath, revisions);
save(join(output, phase + "-status.json"), {
  jobs: jobs.length,
  failures,
  accountedCNY: provider.accountedCNY(),
});
if (failures.length) process.exitCode = 1;
