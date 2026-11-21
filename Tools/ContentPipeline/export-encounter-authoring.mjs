import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";

const root = fileURLToPath(new URL("../../", import.meta.url));
const output = resolve(process.argv[2] ?? join(root, "build/encounter-authoring"));
const readJSON = async (path) => JSON.parse(await readFile(join(root, path), "utf8"));

const app = await readJSON("App/Resources/activity-world-release.json");
const { releaseId } = app;
if (!/^[a-z0-9][a-z0-9-]{1,100}$/.test(releaseId)) throw Error("Invalid App release ID");
const worldPath = `Backend/config/activity-world/${releaseId}.json`;
const world = await readJSON(worldPath);
const { cities, places, characters, stories, media } = world;
if (world.status !== "published" || world.releaseId !== releaseId) {
  throw Error("App and published activity world must share a release ID");
}

const byId = (records) => new Map(records.map((record) => [record.id, record]));
const placeIndex = byId(places);
const storyIndex = byId(stories);
const mediaIndex = byId(media);
const appCards = new Map(app.characters.map(({ npc }) => [npc.id, npc.card]));
const appOutings = new Map(app.preview.outings.filter(({ npc }) => npc).map((outing) => [outing.npc.id, outing]));
const peopleByPlace = new Map(places.map((place) => [place.id, []]));
if (appCards.size !== characters.length || appOutings.size !== stories.length) {
  throw Error("App and published activity world counts differ");
}
for (const person of characters) {
  const binding = person.assignment;
  const place = placeIndex.get(binding?.placeId);
  const story = storyIndex.get(binding?.storyId);
  const outing = appOutings.get(person.id);
  if (!place || place.cityId !== binding.cityId || binding.card.regionId !== binding.cityId ||
      !story || story.npcId !== person.id || story.placeId !== place.id ||
      outing?.placeId !== place.id || outing.cityId !== place.cityId ||
      !isDeepStrictEqual(appCards.get(person.id), binding.card) ||
      !isDeepStrictEqual(outing.npc.card, binding.card) ||
      !isDeepStrictEqual(outing.story, {
        id: story.id, titleZh: story.titleZh, nodes: story.nodes, reunion: story.reunion,
      })) {
    throw Error(`Published and App content differ for ${person.id}`);
  }
  peopleByPlace.get(place.id).push({ person, binding, story });
}

const connectionLabels = {
  grew_up_here: "本地成长",
  settled_here: "长期定居",
  temporary_stay: "短期停留",
};
const table = (value) => String(value).replaceAll("|", "\\|").replace(/\r?\n/g, " ");
const code = (value) => `\`${value}\``;
const field = (label, value) => `- **${label}** ${value}`;
const cardDetail = ({ person, binding, story }) => [
  `<a id="npc-${person.id}"></a>`,
  `### ${binding.card.name}`,
  "",
  field("角色 UUID", code(person.id)),
  field("旅伴号", code(person.travelerId)),
  field("故事 ID", code(story.id)),
  field("地点 ID", code(binding.placeId)),
  field("头像 ID", code(person.avatarId)),
  field("在地经历", connectionLabels[binding.localConnection]),
  field("国籍代码", binding.nationalityCountryCodes.join("、")),
  field("现稿标题", `初遇《${story.titleZh}》 · 重逢《${story.reunion.titleZh}》`),
  field("现稿参考 · 到场", story.causality.presenceReason),
  field("现稿参考 · 地点态度", story.causality.placeAttitude),
  "",
  "发布版完整角色卡",
  "",
  "\`\`\`json",
  JSON.stringify(binding.card, null, 2),
  "\`\`\`",
  "",
].join("\n");

const index = [
  "# 咕游记相遇角色总表",
  "",
  `发布版本 ${code(releaseId)} · ${cities.length} 城 · ${places.length} 地点 · ${characters.length} 人`,
  "",
  "每城文件含全部角色的发布版原卡、绑定 ID 和地点空间事实。上传当前批次的城市文件时，请同时带上 [创作说明](README.md) 和 [交稿模板](story-template.json)。",
  "",
  "| 城市 | 地点数 | 人数 |",
  "| --- | ---: | ---: |",
];
const files = [];
for (const city of cities) {
  const cityPlaces = places.filter((place) => place.cityId === city.id);
  const people = cityPlaces.flatMap((place) => peopleByPlace.get(place.id));
  if (people.length !== city.populationTarget) throw Error(`Unexpected population for ${city.id}`);
  index.push(`| [${city.nameZh}](cities/${city.id}.md) | ${cityPlaces.length} | ${people.length} |`);
  const lines = [
    `# ${city.nameZh} · 相遇角色卡`,
    "",
    `现居城市 ${code(city.id)} · ${cityPlaces.length} 地点 · ${people.length} 人 · ${code(releaseId)}`,
    "",
    "角色卡采用发布版原文。选定角色时复制对应 UUID、故事 ID 和唯一地点 ID。到场和地点态度记录当前故事，可作为重写参考。",
    "",
  ];
  for (const place of cityPlaces) {
    const photo = mediaIndex.get(place.mediaId);
    const residents = peopleByPlace.get(place.id);
    if (!photo || residents.length !== place.populationTarget) throw Error(`Incomplete place ${place.id}`);
    lines.push(
      `## ${place.titleZh}`, "",
      field("唯一地点 ID", code(place.id)),
      field("场景类型", code(place.category)),
      field("实拍照片", `[${photo.author} · 照片来源](${photo.sourceUrl})`),
      "",
      "可确认的空间事实", "",
      ...place.spaceFacts.map((fact) => `- ${fact}`),
      "",
      ...residents.map(cardDetail),
    );
  }
  files.push([join(output, "cities", `${city.id}.md`), lines.join("\n")]);
}
for (const city of cities) {
  index.push("", `## ${city.nameZh}`, "", "| 角色 | 相遇地点 | 国籍 | 职业 | UUID |", "| --- | --- | --- | --- | --- |");
  for (const place of places.filter((item) => item.cityId === city.id)) {
    for (const { person, binding } of peopleByPlace.get(place.id)) {
      const { name, nationality, occupation } = binding.card;
      index.push(`| [${table(name)}](cities/${city.id}.md#npc-${person.id}) | ${table(place.titleZh)} | ${table(nationality)} | ${table(occupation)} | ${code(person.id)} |`);
    }
  }
}

const edges = { start: ["a", "b"], a: ["aa", "ab"], b: ["ba", "bb"], aa: [], ab: [], ba: [], bb: [] };
const beats = () => ["narrator", "npc", "narrator", "npc"].map((speaker, index) => ({
  speaker,
  english: `[English beat ${index + 1}]`,
  chinese: `[第 ${index + 1} 段中文]`,
}));
const template = {
  id: "replace-with-story-id",
  npcId: "00000000-0000-4000-8000-000000000000",
  placeId: "replace-with-place-id",
  titleZh: "[初遇标题]",
  nodes: Object.entries(edges).map(([id, destinations]) => ({
    id,
    beats: beats(),
    choices: destinations.map((next, index) => ({
      english: `[English choice ${index + 1}]`,
      chinese: `[选项 ${index + 1} 的中文]`,
      next,
    })),
  })),
  reunion: { titleZh: "[重逢标题]", beats: beats() },
  causality: {
    presenceReason: "[到场原因]",
    placeAttitude: "[地点态度]",
    stayingConstraint: "[停留约束]",
    currentGoal: "[当下目标]",
    currentState: "[当下状态]",
    contactTrigger: "[搭话触发]",
    characterContinuity: "[人物设定如何体现]",
    reactionAndChange: "[aa、ab、ba、bb 各自的反应和结果]",
    spatialContinuity: "[空间、时间、物件与动作连续性]",
    reunionCommonFacts: "[所有旧识都成立的事实]",
  },
  reviewStatus: "draft",
  reviewEvidence: [],
};

await mkdir(join(output, "cities"), { recursive: true });
const guide = join(root, "Content/ActivityWorld/2026-10-31-places-v1/authoring/README.md");
await Promise.all([
  copyFile(guide, join(output, "README.md")),
  writeFile(join(output, "story-template.json"), JSON.stringify(template, null, 2) + "\n"),
  writeFile(join(output, "index.md"), index.join("\n") + "\n"),
  ...files.map(([path, text]) => writeFile(path, text)),
]);
console.log(`Exported ${characters.length} cards across ${cities.length} cities and ${places.length} places to ${output}`);
