import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { projectActivityStory } from "./activity-world-editorial.mjs";

const [worldPath, assignmentPath, authoringDirectory, outputPath] =
  process.argv.slice(2);
if (!outputPath)
  throw Error(
    "Usage: assemble-activity-world.mjs world.json assignments.json authoring-directory output.json",
  );
const read = (path) => JSON.parse(readFileSync(path, "utf8"));
const world = read(worldPath);
const bindings = read(assignmentPath).characters;
const revisionsPath = join(authoringDirectory, "revisions.json");
const revisions = existsSync(revisionsPath) ? read(revisionsPath) : {};
const timeZones = {
  london: "Europe/London",
  newyork: "America/New_York",
  singapore: "Asia/Singapore",
  sydney: "Australia/Sydney",
  melbourne: "Australia/Melbourne",
  toronto: "America/Toronto",
  vancouver: "America/Vancouver",
  edinburgh: "Europe/London",
  dublin: "Europe/Dublin",
  auckland: "Pacific/Auckland",
  capetown: "Africa/Johannesburg",
  manchester: "Europe/London",
  neworleans: "America/Chicago",
  nairobi: "Africa/Nairobi",
  kingston: "America/Jamaica",
};
const people = new Map(world.characters.map((person) => [person.id, person]));
const places = new Map(world.places.map((place) => [place.id, place]));
if (
  bindings.length !== 200 ||
  new Set(bindings.map((binding) => binding.npcId)).size !== 200
) {
  throw Error("Expected exactly 200 distinct bindings");
}
for (const city of world.cities) {
  if (
    bindings.filter((binding) => binding.cityId === city.id).length !==
    city.populationTarget
  ) {
    throw Error("City quota mismatch " + city.id);
  }
}
for (const place of world.places) {
  if (
    bindings.filter((binding) => binding.placeId === place.id).length !==
    place.populationTarget
  ) {
    throw Error("Place quota mismatch " + place.id);
  }
}

const stories = [];
for (const binding of bindings) {
  const person = people.get(binding.npcId);
  const place = places.get(binding.placeId);
  if (!person || place?.cityId !== binding.cityId)
    throw Error("Unknown or cross-city binding " + binding.npcId);
  if (binding.lockedStoryId) {
    const story = world.stories.find(
      (story) => story.id === binding.lockedStoryId,
    );
    if (
      !story ||
      story.npcId !== person.id ||
      person.assignment?.placeId !== place.id
    ) {
      throw Error("Existing story binding changed " + person.id);
    }
    const projected = projectActivityStory(
      {
        ...story,
        background: person.assignment.card.background,
        migrationExplanationZh: person.assignment.migrationExplanationZh,
      },
      {
        originalCard: person.originalCard,
        binding,
        placeTitleZh: place.titleZh,
      },
    );
    person.assignment.card.background = projected.background;
    person.assignment.migrationExplanationZh = projected.migrationExplanationZh;
    stories.push({
      ...story,
      reunion: projected.reunion,
      causality: projected.causality,
    });
    continue;
  }
  const receiptKey = revisions[person.id] ?? "first-v10-" + person.id;
  if (!/^[a-z0-9-]+$/.test(receiptKey))
    throw Error("Invalid authoring receipt key");
  const resultPath = join(authoringDirectory, receiptKey + ".result.json");
  const result = projectActivityStory(read(resultPath), {
    originalCard: person.originalCard,
    binding,
    placeTitleZh: place.titleZh,
  });
  const storyId = "first-" + person.id + "-places-v1";
  const card = {
    ...structuredClone(person.originalCard),
    regionId: binding.cityId,
    nationality: binding.nationalityLabel,
    hometown: binding.hometown,
    background: result.background,
  };
  if (card.activityProfile)
    card.activityProfile.timeZoneIdentifier = timeZones[binding.cityId];
  person.assignment = {
    cityId: binding.cityId,
    placeId: place.id,
    storyId,
    nationalityCountryCodes: binding.nationalityCountryCodes,
    nationalityLabel: binding.nationalityLabel,
    hometown: binding.hometown,
    localConnection: binding.localConnection,
    presenceReason: result.causality.presenceReason,
    placeAttitude: result.causality.placeAttitude,
    fit: result.fit,
    fitEvidence: result.fitEvidence,
    migrationExplanationZh: result.migrationExplanationZh,
    card,
  };
  person.reviewStatus = "pending";
  person.reviewNotes = [
    "城市与地点由固定清单分配；原身份、头像、核心资料基线保留。剧情与资料为作者草稿，正式发布审校待完成。",
  ];
  stories.push({
    id: storyId,
    npcId: person.id,
    placeId: place.id,
    titleZh: result.titleZh,
    nodes: result.nodes,
    reunion: result.reunion,
    causality: result.causality,
    reviewStatus: "draft",
    reviewEvidence: [
      "作者稿回执 " + receiptKey,
      "作者稿 SHA256 " +
        createHash("sha256").update(readFileSync(resultPath)).digest("hex"),
      "结构校验、模型复核与正式编辑批准分别记录；本条保持草稿状态。",
    ],
  });
}
world.status = "draft";
world.stories = stories;
writeFileSync(outputPath, JSON.stringify(world, null, 2) + "\n");
console.log(
  JSON.stringify({
    characters: bindings.length,
    places: places.size,
    stories: stories.length,
    status: world.status,
  }),
);
