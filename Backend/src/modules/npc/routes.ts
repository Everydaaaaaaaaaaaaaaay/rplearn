import type { FastifyInstance } from "fastify";
import { z, type ZodType } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import type { NpcService } from "./service.js";
import { isValidTravelerId } from "./traveler-id.js";

const uuid = z.uuid().transform((value) => value.toLowerCase());
const nullableText = (maximum: number) =>
  z
    .string()
    .trim()
    .min(1)
    .max(maximum)
    .nullable()
    .optional()
    .transform((value) => value ?? null);
const shortList = (maximumItems: number, maximumLength = 120) =>
  z.array(z.string().trim().min(1).max(maximumLength)).max(maximumItems);

const personaVoice = z
  .object({
    anchorLines: shortList(8, 240),
    boundaries: shortList(8, 240),
    conversationalHabits: shortList(10, 240),
    flaws: shortList(6, 160),
    values: shortList(8, 160),
  })
  .strict();

const publicCard = z
  .object({
    age: z.number().int().min(14).max(100),
    appearance: z.string().trim().min(1).max(2_000),
    background: nullableText(4_000),
    birthday: z
      .string()
      .regex(/^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/)
      .nullable()
      .optional()
      .transform((value) => value ?? null),
    gender: z.enum(["female", "male", "other"]),
    hobbies: shortList(12, 80).min(1),
    hometown: nullableText(160),
    languages: shortList(12, 80),
    name: z.string().trim().min(1).max(80),
    nationality: z.string().trim().min(1).max(80),
    occupation: z.string().trim().min(1).max(120),
    personaVoice,
    personality: z.string().trim().min(1).max(2_000),
    regionId: z.string().regex(/^[a-z0-9-]{2,64}$/),
    signature: nullableText(240),
    speechStyle: nullableText(2_000),
  })
  .strict();

const registerBody = z
  .object({
    card: publicCard,
    id: uuid,
    requiredAvatarTags: z
      .array(
        z
          .string()
          .regex(
            /^(body|outfit|theme|frame|glasses|hair|facing|perspective|pose|use|face|expression):[a-z0-9-]{1,40}$/,
          ),
      )
      .max(12)
      .optional(),
  })
  .strict();
const relationshipBody = z
  .object({
    localCharacterId: uuid,
    status: z.enum(["candidate", "friend", "removed"]),
  })
  .strict();
const npcParameters = z.object({ npcId: uuid }).strict();
const travelerParameters = z
  .object({ travelerId: z.string().regex(/^[0-9]{11}$/) })
  .strict();

function parse<T>(schema: ZodType<T>, value: unknown): T {
  const result = schema.safeParse(value);
  if (result.success) return result.data;
  throw new AppError({
    code: "INVALID_REQUEST",
    details: result.error.issues.map((issue) => ({
      code: issue.code,
      message: issue.message,
      path: issue.path,
    })),
    message: "The request is invalid.",
    statusCode: 400,
  });
}

export function registerNpcRoutes(
  app: FastifyInstance,
  authService: AuthService,
  npcService: NpcService,
): void {
  app.post(
    "/v1/npcs",
    { schema: { security: [{ bearerAuth: [] }], tags: ["npcs"] } },
    async (request, reply) => {
      const identity = await authenticateRequest(request, authService);
      const input = parse(registerBody, request.body);
      reply.header("cache-control", "no-store");
      return npcService.register(identity.userId, input);
    },
  );

  app.get(
    "/v1/npcs/by-traveler-id/:travelerId",
    { schema: { tags: ["npcs"] } },
    async (request, reply) => {
      const { travelerId } = parse(travelerParameters, request.params);
      if (!isValidTravelerId(travelerId)) {
        throw new AppError({
          code: "NPC_NOT_FOUND",
          message: "No public NPC has that traveler ID.",
          statusCode: 404,
        });
      }
      reply.header("cache-control", "public, max-age=300");
      return npcService.find(travelerId);
    },
  );

  app.put(
    "/v1/npcs/:npcId/relationship",
    { schema: { security: [{ bearerAuth: [] }], tags: ["npcs"] } },
    async (request, reply) => {
      const identity = await authenticateRequest(request, authService);
      const { npcId } = parse(npcParameters, request.params);
      const input = parse(relationshipBody, request.body);
      await npcService.link(identity.userId, npcId, input);
      return reply.status(204).send();
    },
  );
}
