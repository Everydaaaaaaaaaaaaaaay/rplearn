import { publicCard } from "./card-schema.js";
import { authoredActions } from "./authored-content.js";
import type { FastifyInstance } from "fastify";
import { z, type ZodType } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateActorRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import type { NpcService } from "./service.js";
import { isValidTravelerId } from "./traveler-id.js";
import {
  backgroundMotifs,
  interactionStyles,
  interestDomains,
  occupationDomains,
  socialRoles,
  traits,
} from "./persona-diversity.js";

const uuid = z.uuid().transform((value) => value.toLowerCase());
const diversityProfile = z
  .object({
    version: z.literal(1),
    occupationDomain: z.enum(occupationDomains),
    socialRole: z.enum(socialRoles),
    interactionStyle: z.enum(interactionStyles),
    interestDomains: z.array(z.enum(interestDomains)).min(1).max(4),
    traits: z.array(z.enum(traits)).min(2).max(4),
    backgroundMotif: z.enum(backgroundMotifs),
    energy: z.enum(["low", "medium", "high"]),
    warmth: z.enum(["reserved", "balanced", "warm"]),
    structure: z.enum(["spontaneous", "balanced", "structured"]),
  })
  .strict();

const registerBody = z
  .object({
    card: publicCard,
    diversityProfile: diversityProfile.optional(),
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
    encounterContext: z
      .object({
        regionId: z.string().regex(/^[a-z0-9-]{2,64}$/),
        activityId: z.string().regex(/^[a-zA-Z0-9_-]{1,128}$/),
        category: z.enum(["culture", "food", "outdoors", "social", "night"]),
        language: z.string().trim().min(1).max(80),
      })
      .strict()
      .optional(),
  })
  .strict();
const diversityReviewBody = z
  .object({
    card: publicCard,
    diversityProfile,
    encounterContext: registerBody.shape.encounterContext.unwrap(),
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
    "/v1/npcs/diversity-review",
    { schema: { security: [{ bearerAuth: [] }], tags: ["npcs"] } },
    async (request, reply) => {
      const identity = await authenticateActorRequest(request, authService);
      const input = parse(diversityReviewBody, request.body);
      reply.header("cache-control", "no-store");
      return npcService.reviewDiversity(identity.userId, input);
    },
  );
  app.post("/v1/npcs/encounters", { schema: { tags: ["npcs"] } }, async (request) => {
    const identity = await authenticateActorRequest(request, authService);
    const context = parse(registerBody.shape.encounterContext.unwrap(), request.body);
    return npcService.selectEncounter(identity.userId, context);
  });
  app.post(
    "/v1/npcs/authored-encounters",
    { schema: { tags: ["npcs"] } },
    async (request, reply) => {
      const identity = await authenticateActorRequest(request, authService);
      const input = parse(
        z
          .object({
            context: registerBody.shape.encounterContext.unwrap().extend({
              activityId: z.enum(authoredActions),
              category: z.literal("social"),
              language: z.literal("English"),
            }),
            libraryVersion: z.string().regex(/^[a-z0-9-]{1,80}$/),
            runId: uuid,
          })
          .strict(),
        request.body,
      );
      reply.header("cache-control", "no-store");
      return npcService.selectEncounter(identity.userId, input.context, {
        libraryVersion: input.libraryVersion,
        runId: input.runId,
      });
    },
  );
  app.post(
    "/v1/npcs",
    { schema: { security: [{ bearerAuth: [] }], tags: ["npcs"] } },
    async (request, reply) => {
      const identity = await authenticateActorRequest(request, authService);
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
      const identity = await authenticateActorRequest(request, authService);
      const { npcId } = parse(npcParameters, request.params);
      const input = parse(relationshipBody, request.body);
      await npcService.link(identity.userId, npcId, input);
      return reply.status(204).send();
    },
  );
}
