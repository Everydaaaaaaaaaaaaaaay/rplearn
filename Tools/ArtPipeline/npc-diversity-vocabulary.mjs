// Concrete visual variations. Palette is intentionally NOT an identity dimension.
export const faceBases = [
  "short round face with full cheeks and a short rounded chin",
  "long oblong face with long midface and a small recessed chin",
  "broad square face with horizontal jaw corners and short lower face",
  "soft rectangular face with low full cheeks and a rounded jaw",
  "diamond face with broad lateral cheekbones and narrow temples",
  "oval face with slightly uneven cheeks and a softly offset chin",
  "long rectangular face with hollow cheek planes and blunt long chin",
  "wide forehead tapering to a compact blunt lower face",
  "short broad face with low hairline and broad lower cheeks",
  "narrow forehead widening to a heavy angular jaw",
  "long soft face with high forehead and rounded long chin",
  "compact angular face with short midface and very wide jaw corners",
];
export const featureSets = [
  "small wide-set heavy-lidded eyes, thick low horizontal eyebrows, a short wide nose contour, a wide thin mouth",
  "close-set narrow eyes, thin high curved eyebrows, long convex nose silhouette, very short closed mouth",
  "wide-set round eyes, separated thick rising brows, short upturned nose silhouette, broad mouth with unequal corners",
  "small deep-set downward eyes, low heavy straight brows, prominent straight long nose, narrow mouth",
  "asymmetric upper eyelids, sparse broken angular brows, broad gently bent nose, full-width softly curved mouth",
];
export const faces = faceBases.flatMap((base, i) =>
  featureSets.map((features, j) => ({
    id: `face-${i + 1}-${j + 1}`,
    description: `${base}; ${features}`,
  })),
);
const hairGroups = [
  [
    "uniform shaved scalp",
    "shaved scalp with stubble horseshoe at back",
    "bald crown with short side tufts",
    "bald crown with long side hair tucked behind ears",
    "smooth scalp with a short centered rear braid",
  ],
  [
    "uniform close buzz cut",
    "flat top with sharply squared corners",
    "short crew cut with widow peak",
    "very short Caesar crop and flat fringe",
    "short brush cut with high sides",
  ],
  [
    "tight small curls rounded close to scalp",
    "short tight curls with flat high top",
    "high compact tight curls with shaved sides",
    "short tight curls swept into asymmetric silhouette",
    "compact coiled curls with broad temple volume",
  ],
  [
    "loose short curls forming wide round silhouette",
    "medium large curls with center part",
    "long loose curls behind both shoulders",
    "short curls with narrow top and wide sides",
    "soft curly fringe over a cropped back",
  ],
  [
    "short straight bob with blunt jawline ends",
    "short bob tucked behind both ears",
    "asymmetric bob long on one side",
    "rounded bob with thick straight fringe",
    "wavy bob with deep side part",
  ],
  [
    "short pixie with exposed ears",
    "long-top pixie with swept fringe",
    "textured pixie with upright front silhouette",
    "smooth center-parted pixie",
    "cropped pixie with small pointed nape",
  ],
  [
    "long straight hair with center part",
    "long straight hair with blunt full fringe",
    "long straight hair tucked behind one ear",
    "long straight hair swept entirely over one shoulder",
    "long straight hair with side-swept fringe",
  ],
  [
    "shoulder-length waves with center part",
    "shoulder-length waves with deep side part",
    "outward-flipped shoulder-length ends",
    "soft shoulder-length shag with narrow fringe",
    "wide shoulder-length waves with exposed forehead",
  ],
  [
    "single low tied ponytail with clean forehead",
    "high ponytail with short curved fringe",
    "side ponytail below one ear",
    "short ponytail with center-parted front strands",
    "thick low ponytail with swept-back top",
  ],
  [
    "compact low centered bun",
    "high compact top bun",
    "large low side bun",
    "two small low buns behind ears",
    "elongated vertical bun with center-parted front",
  ],
  [
    "single thick braid over shoulder",
    "two thick braids forward over shoulders",
    "many thin braids tied behind head",
    "crown braid with exposed forehead",
    "short box-braid bob",
  ],
  [
    "short swept-back hair with receding temples",
    "deep receding M hairline and close side cut",
    "high receding forehead with short side part",
    "receding crown with wavy nape-length hair",
    "widow peak with swept-back narrow top",
  ],
  [
    "short straight bowl cut exposing ears",
    "long bowl cut covering ears",
    "curved bowl fringe with shaved undercut",
    "asymmetric bowl cut with one temple exposed",
    "flat heavy bowl fringe and short nape",
  ],
  [
    "medium messy layered shag",
    "short spiky outward silhouette",
    "medium upright spiky top with narrow sides",
    "long jagged layered hair behind neck",
    "short tousled hair with offset crown volume",
  ],
  [
    "slicked-back medium hair at nape",
    "smooth severe side part and tapered nape",
    "short center part opening forehead",
    "long swept-back hair tucked behind ears",
    "smooth combed-over short hair with a high forehead",
  ],
  [
    "entirely white close short crop",
    "entirely white rounded bob",
    "entirely white long low ponytail",
    "entirely white swept-back waves",
    "entirely white compact curly hair",
  ],
];
export const hairstyles = hairGroups.flatMap((group, i) =>
  group.map((description, j) => ({
    id: `hair-${i + 1}-${j + 1}`,
    description: (i === 15 ? "" : "one near-black mass, ") + description,
  })),
);
const emotions = [
  ["joy", "raised cheeks, crescent eyes, both mouth corners up"],
  ["skepticism", "one brow high, other low, uneven narrow eyelids"],
  ["focus", "brows lowered inward, narrow intent eyes"],
  ["surprise", "both brows raised high, round open eyes"],
  ["shyness", "gaze averted down, sloped brows, inward-tucked chin"],
  ["fatigue", "heavy drooping eyelids, low uneven brows"],
  ["pride", "chin raised, lowered half-lids, one brow softly arched"],
  ["concern", "inner brows raised, tense lower eyelids"],
  ["delight", "eyes squeezed pleasantly, high cheeks"],
  ["mischief", "one eye narrowed more, eyebrow raised on opposite side"],
  ["resolve", "firm flat brows, steady direct eyes"],
  ["curiosity", "asymmetric raised brows, eyes tracking sideways upward"],
  ["annoyance", "brows sharply lowered, alert widened eyes"],
  ["drowsiness", "nearly closed eyes, relaxed low brows"],
  ["warmth", "relaxed curved eye corners, raised cheeks"],
  ["hesitation", "asymmetrically raised brows, sideways gaze"],
];
const mouthActions = [
  ["closed", "mouth closed in a short off-center line appropriate to emotion"],
  [
    "open",
    "mouth visibly open as if reacting mid-word, one simple dark shape, no detailed teeth",
  ],
  [
    "pressed",
    "lips pressed and slightly pulled to one side, cheeks asymmetrically compressed",
  ],
  [
    "tooth-band",
    "mouth wider with one simple white tooth band, strong corners appropriate to emotion",
  ],
  [
    "small-part",
    "mouth gently parted with a short dark gap, one corner higher, subtle chin shift",
  ],
];
export const expressions = emotions.flatMap(([name, eyes], i) =>
  mouthActions.map(([shape, mouth], j) => ({
    id: `expression-${i + 1}-${j + 1}`,
    description: `${name}: ${eyes}; ${mouth}`,
    eyes,
    mouth,
  })),
);
const bodyActions = [
  "back to viewer, head looking over shoulder",
  "one shoulder raised toward cheek, opposite shoulder lowered",
  "leaning forward, neck shortened naturally",
  "leaning back slightly, chin elevated",
  "one hand softly supporting cheek, fingers grouped below ear",
  "one hand pinching collar at collarbone",
  "two fingers touching temple, eyes unobscured",
  "one hand adjusting a broad scarf across chest",
  "back of fingers resting under chin",
  "head tipped sideways as if listening",
  "upper edges of folded arms at lower crop",
  "one hand gripping a wide shoulder strap",
];
const neckActions = [
  "head upright and gaze direct",
  "head leaning toward near shoulder, gaze sideways",
  "chin tucked and eyes raised",
  "chin lifted with throat silhouette visible",
  "head turned opposite torso, shoulders strongly diagonal",
];
export const poses = bodyActions.flatMap((base, i) =>
  neckActions.map((head, j) => ({
    id: `pose-${i + 1}-${j + 1}`,
    description: `${base}; ${head}`,
  })),
);
export const cameras = [
  "front",
  "three-quarter-left",
  "three-quarter-right",
  "profile-left",
  "profile-right",
].flatMap((yaw) =>
  ["eye-level", "high-angle", "low-angle"].map((pitch) => ({
    id: `${yaw}-${pitch}`,
    yaw,
    pitch,
    description: `${yaw}, ${pitch}`,
  })),
);
const garmentBases = [
  "tailored blazer",
  "soft knit cardigan",
  "utility work vest",
  "loose athletic hoodie",
  "structured track jacket",
  "plain apron over shirt",
  "outdoor field jacket",
  "soft studio smock",
  "sleeveless layered waistcoat",
  "collarless loose coat",
  "denim-cut overshirt",
  "wide soft pullover",
];
const necklines = [
  "broad open collar showing plain crew-neck inner layer",
  "high close collar framing neck",
  "asymmetric wrapped scarf collar",
  "wide rounded neckline exposing collarbone shape",
  "buttoned narrow stand collar with one bold opening",
];
export const outfits = garmentBases.flatMap((base, i) =>
  necklines.map((neck, j) => ({
    id: `outfit-${i + 1}-${j + 1}`,
    description: `${base}, ${neck}`,
  })),
);
export const counts = {
  faces: faces.length,
  expressions: expressions.length,
  hairstyles: hairstyles.length,
  poses: poses.length,
  cameras: cameras.length,
  outfits: outfits.length,
};
if (Object.values(counts).some((n) => n < 15))
  throw Error("Incomplete diversity vocabulary");
