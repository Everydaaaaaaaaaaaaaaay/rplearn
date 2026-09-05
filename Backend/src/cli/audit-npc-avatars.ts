import { readFile } from "node:fs/promises";
import { z } from "zod";
import { avatarManifestSchema } from "../modules/npc/avatar-catalog.js";
import { auditAvatarCoverage } from "../modules/npc/avatar-coverage.js";
import { cultureMap } from "../modules/npc/culture-map.js";

async function main() {
  const [manifestPath, personasPath] = process.argv
    .slice(2)
    .filter((arg) => arg !== "--");
  if (!manifestPath)
    throw new Error("Usage: pnpm npc-avatars:audit -- manifest.json [personas.json]");
  const manifest = avatarManifestSchema.parse(
    JSON.parse(await readFile(manifestPath, "utf8")) as unknown,
  );
  const personas = personasPath
    ? z
        .array(
          z
            .object({
              id: z.string().min(1),
              hobbies: z.array(z.string().min(1)).min(1),
              personality: z.string(),
            })
            .strict(),
        )
        .parse(JSON.parse(await readFile(personasPath, "utf8")) as unknown)
    : cultureMap.map(([id]) => ({ id, hobbies: [id], personality: "" }));
  process.stdout.write(
    `${JSON.stringify(auditAvatarCoverage(manifest, personas), null, 2)}\n`,
  );
}
void main().catch((error: unknown) => {
  process.stderr.write(`${String(error)}\n`);
  process.exitCode = 1;
});
