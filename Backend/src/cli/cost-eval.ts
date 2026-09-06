import "dotenv/config";
import { z } from "zod";
import { createCreditService } from "../modules/access/credit-service.js";
import { decimalUnits } from "../modules/access/credit-pricing.js";
import { execFileSync } from "node:child_process";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { resolve } from "node:path";
import { randomUUID, createHash } from "node:crypto";
import { loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { runMigrations } from "../db/migrate.js";
import { createAuthService } from "../modules/auth/service.js";
import {
  summarizeSession,
  pricingSensitivity,
  type SessionEvidence,
  type LedgerCall,
} from "../evaluations/cost-report.js";

const scenariosSchema = z
  .object({
    personas: z
      .array(
        z.object({
          id: z.string().regex(/^[a-z0-9-]{1,64}$/),
          label: z.string().min(1),
          plan: z.enum(["guest", "free", "plus", "pro"]),
          difficulty: z
            .enum(["primary3", "junior3", "undergraduate", "advanced"])
            .default("junior3"),
          utterances: z.array(z.string().min(1).max(10000)).optional(),
          characters: z
            .array(
              z.object({
                name: z.string(),
                age: z.number().int(),
                gender: z.enum(["male", "female", "other"]),
                nationality: z.string(),
                regionID: z.string(),
                occupation: z.string(),
                hobbies: z.array(z.string()),
                appearance: z.string(),
                personality: z.string(),
                speechStyle: z.string(),
                background: z.string(),
              }),
            )
            .min(1)
            .max(3)
            .optional(),
          switchEvery: z.number().int().min(0).default(0),
          reopenEvery: z.number().int().min(0).default(0),
          quizEnabled: z.boolean().default(true),
          turnCount: z.number().int().positive().max(200),
          encounters: z.number().int().min(0).max(20),
          grammarEvery: z.number().int().min(0),
          translateEvery: z.number().int().min(0),
          voice: z.boolean(),
          reopenAt: z.number().int().min(0),
          activeMinutesEstimate: z.number().positive(),
          activeDaysPerMonthAssumption: z.number().int().min(1).max(31),
        }),
      )
      .min(1),
    utterances: z.array(z.string().min(1).max(10000)).min(1),
  })
  .superRefine((value, ctx) => {
    if (new Set(value.personas.map((p) => p.id)).size !== value.personas.length)
      ctx.addIssue({ code: "custom", message: "Persona IDs must be unique" });
    if (
      value.personas.some(
        (p) => p.turnCount > (p.utterances ?? value.utterances).length,
      )
    )
      ctx.addIssue({
        code: "custom",
        message: "Every planned turn needs an actual scripted utterance",
      });
  });
type Persona = z.infer<typeof scenariosSchema>["personas"][number] & {
  scenarioId: string;
  replicate: number;
};
interface Manifest {
  runId: string;
  baseURL: string;
  outputDirectory: string;
  scenarioHash: string;
  cases: (Omit<Persona, "scenarioId" | "replicate" | "difficulty"> &
    Partial<Pick<Persona, "scenarioId" | "replicate" | "difficulty">> & {
      userId: string;
      refreshToken: string;
      refreshTokenExpiresAt: string;
      sessionId: string;
      utterances: string[];
    })[];
}
async function main() {
  const [command, directoryArg] = process.argv.slice(2);
  if (!directoryArg)
    throw new Error("Usage: cost-eval prepare|report OUTPUT_DIRECTORY");
  const config = loadConfig({ ...process.env, NODE_ENV: "test" });
  const dbURL = new URL(config.databaseUrl);
  if (
    !["localhost", "127.0.0.1"].includes(dbURL.hostname) ||
    !/^\/lingotrip_cost_eval_[a-z0-9_]+$/.test(dbURL.pathname)
  )
    throw new Error("Requires dedicated loopback database named lingotrip_cost_eval_*");
  const directory = resolve(directoryArg),
    database = createDatabase(config);
  await mkdir(directory, { recursive: true, mode: 0o700 });
  try {
    if (command === "prepare") {
      await runMigrations(database);
      const [existing] = await database.sql<
        { count: number }[]
      >`select count(*)::int as count from app.users`;
      if (existing?.count)
        throw new Error(
          "Preparation requires a fresh isolated database; existing data will not be erased",
        );
      if (process.env.COST_EVAL_FREE_CREDITS !== undefined) {
        const credits = Number(process.env.COST_EVAL_FREE_CREDITS);
        if (!Number.isSafeInteger(credits) || credits < 1 || credits > 400)
          throw new Error("Experimental free allowance must be 1...400 credits");
        await database.sql`update app.service_metadata set value=value || ${JSON.stringify({ version: `cost-eval-free-${String(credits)}`, free: String(BigInt(credits) * 1_000_000n) })}::jsonb where key='model-credits-v1'`;
      }
      const scenarioSource = await readFile(
        process.env.COST_EVAL_SCENARIOS ??
          new URL("../../config/cost-scenarios.json", import.meta.url),
        "utf8",
      );
      const scenarios = scenariosSchema.parse(JSON.parse(scenarioSource));
      const auth = await createAuthService(config, database);
      const cases: Manifest["cases"] = [];
      const creditService = createCreditService(database);
      let budgetUnits = 0n;
      const replicates = Number(process.env.COST_EVAL_REPLICATES ?? "1");
      if (!Number.isInteger(replicates) || replicates < 1 || replicates > 10)
        throw new Error("Replicates must be 1...10");
      const personas = Array.from({ length: replicates }, (_, index) =>
        scenarios.personas.map((p) => ({
          ...p,
          scenarioId: p.id,
          replicate: index + 1,
          id: replicates === 1 ? p.id : `${p.id}-r${String(index + 1)}`,
        })),
      ).flat();
      for (const persona of personas) {
        const id = randomUUID();
        await database.sql`insert into app.users(id) values(${id})`;
        if (persona.plan === "guest")
          await database.sql`insert into app.guest_installations(user_id,installation_hash) values(${id},${createHash("sha256").update(id).digest("hex")})`;
        if (["plus", "pro"].includes(persona.plan))
          await database.sql`insert into app.entitlement_grants(id,user_id,plan_id,entitlement_key,environment,source_provider,source_reference_id,status,provider_event_at,valid_until)
       values(${randomUUID()},${id},${persona.plan},'subscription','test','manual',${randomUUID()},'active',now(),now()+interval '12 hours')`;
        budgetUnits += BigInt(
          Math.round((await creditService.snapshot(id)).limit * 1_000_000),
        );
        const token = await auth.loginFederated(
          id,
          0,
          { deviceId: `cost-eval-${persona.id}`, platform: "unknown" },
          auth.createRequestMetadata("127.0.0.1", "cost-eval"),
        );
        cases.push({
          ...persona,
          userId: id,
          refreshToken: token.refreshToken,
          refreshTokenExpiresAt: token.refreshTokenExpiresAt.toISOString(),
          sessionId: token.sessionId,
          utterances: (persona.utterances ?? scenarios.utterances)
            .slice(0, persona.turnCount)
            .map((text) =>
              persona.encounters > 0 ? text.replace("Hi Oliver!", "Hi!") : text,
            ),
        });
      }
      if (budgetUnits > decimalUnits(process.env.COST_EVAL_MAX_CNY ?? "4", 9))
        throw new Error(
          "The actual isolated account budgets exceed COST_EVAL_MAX_CNY; no model requests were made",
        );
      const manifest: Manifest = {
        runId: randomUUID(),
        baseURL: process.env.COST_EVAL_BASE_URL ?? "http://127.0.0.1:55452",
        outputDirectory: directory,
        scenarioHash: createHash("sha256").update(scenarioSource).digest("hex"),
        cases,
      };
      await writeFile(
        resolve(directory, "private-config.json"),
        JSON.stringify(manifest),
        { mode: 0o600 },
      );
      const routes = await database.sql`select * from app.ai_routes order by task`;
      const policy =
        await database.sql`select key,value from app.service_metadata where key in ('model-credits-v1','guest-access-policy-v1')`;
      await writeFile(
        resolve(directory, "environment.json"),
        JSON.stringify(
          {
            runId: manifest.runId,
            scenarioHash: manifest.scenarioHash,
            sourceRevision: execFileSync("git", ["rev-parse", "HEAD"], {
              encoding: "utf8",
            }).trim(),
            sourceDirty:
              execFileSync("git", ["status", "--porcelain"], {
                encoding: "utf8",
              }).trim().length > 0,
            scenarioInputs: cases.map((c) => ({
              id: c.id,
              scenarioId: c.scenarioId,
              replicate: c.replicate,
              label: c.label,
              plan: c.plan,
              difficulty: c.difficulty,
              utterances: c.utterances,
              characters: c.characters,
              turnCount: c.turnCount,
              encounters: c.encounters,
              grammarEvery: c.grammarEvery,
              translateEvery: c.translateEvery,
              voice: c.voice,
              reopenAt: c.reopenAt,
              reopenEvery: c.reopenEvery,
              switchEvery: c.switchEvery,
              quizEnabled: c.quizEnabled,
              activeMinutesEstimate: c.activeMinutesEstimate,
              activeDaysPerMonthAssumption: c.activeDaysPerMonthAssumption,
            })),
            routes,
            policy,
            createdAt: new Date().toISOString(),
            maximumNominalSessionBudgetsCny: Number(budgetUnits) / 1e9,
          },
          null,
          2,
        ),
      );
      process.stdout.write(
        `Prepared ${String(cases.length)} isolated personas. Credential file is private-config.json; do not publish it.\n`,
      );
    } else if (command === "select-unstarted" || command === "verify-unstarted") {
      const manifest = JSON.parse(
        await readFile(resolve(directory, "private-config.json"), "utf8"),
      ) as Manifest;
      const environment = JSON.parse(
        await readFile(resolve(directory, "environment.json"), "utf8"),
      ) as { createdAt: string };
      if (environment.createdAt.slice(0, 10) !== new Date().toISOString().slice(0, 10))
        throw new Error("Do not reuse an evaluation across credit issuance days");
      const selected: Manifest["cases"] = [];
      const excluded: { id: string; reason: string }[] = [];
      for (const persona of manifest.cases) {
        const [row] = await database.sql<
          { count: number }[]
        >`select count(*)::int as count from app.credit_operations where user_id=${persona.userId}`;
        let hasEvidence = false;
        try {
          await readFile(resolve(directory, `${persona.id}.json`), "utf8");
          hasEvidence = true;
        } catch (error) {
          if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
        }
        if (hasEvidence || (row?.count ?? 0) > 0)
          excluded.push({
            id: persona.id,
            reason: hasEvidence
              ? "native_sample_already_started"
              : "ledger_already_exists",
          });
        else selected.push(persona);
      }
      if (!selected.length)
        throw new Error(
          "No unstarted samples remain; existing paid evidence will not be overwritten",
        );
      if (command === "verify-unstarted") {
        if (excluded.length)
          throw new Error(
            "Setup resume requires every sample to have zero ledger calls and no native evidence",
          );
        process.stdout.write(
          "Verified all samples are unstarted in the database and evidence directory.\n",
        );
        return;
      }
      await writeFile(
        resolve(directory, "private-next-config.json"),
        JSON.stringify({ ...manifest, cases: selected }),
        { mode: 0o600 },
      );
      await writeFile(
        resolve(directory, `continuation-${String(Date.now())}.json`),
        JSON.stringify(
          {
            at: new Date().toISOString(),
            selected: selected.map((p) => p.id),
            excluded,
          },
          null,
          2,
        ),
      );
      process.stdout.write(
        `Selected ${String(selected.length)} never-started samples; ${String(excluded.length)} existing samples retained.\n`,
      );
    } else if (command === "report") {
      const manifest = JSON.parse(
        await readFile(resolve(directory, "private-config.json"), "utf8"),
      ) as Manifest;
      let annotations: { environmentInterruptedIds: string[]; reason?: string } = {
        environmentInterruptedIds: [],
      };
      try {
        annotations = JSON.parse(
          await readFile(resolve(directory, "environment-interruptions.json"), "utf8"),
        ) as typeof annotations;
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      }
      const sessions: SessionEvidence[] = [];
      for (const persona of manifest.cases) {
        let native: {
          status: string;
          completedTurns: number;
          actions: SessionEvidence["actions"];
          calls?: SessionEvidence["nativeCalls"];
          turns?: unknown[];
          characterCards?: unknown[];
          startingCredits?: number;
          endingCredits?: number;
        } = { status: "missing_native_evidence", completedTurns: 0, actions: [] };
        try {
          native = JSON.parse(
            await readFile(resolve(directory, `${persona.id}.json`), "utf8"),
          ) as typeof native;
        } catch {
          /* incomplete runs remain visible */
        }
        const ledger = await database.sql<
          LedgerCall[]
        >`select c.operation_id::text as "operationId",c.task,c.status,c.reserved_units::text as "reservedUnits",c.settled_units::text as "settledUnits",c.usage,c.price,c.created_at::text as "createdAt",
          a.config_version as "routeConfigVersion",a.provider_attempts as "providerAttempts",a.latency_ms as "latencyMs",c.provider_request_id as "providerRequestId", c.dispatched_at::text as "dispatchedAt", c.completed_at::text as "completedAt", c.reason
          from app.credit_operations c left join app.ai_requests a on a.user_id=c.user_id and a.operation_id=c.operation_id where c.user_id=${persona.userId} order by c.created_at`;
        sessions.push({
          id: persona.id,
          scenarioId: persona.scenarioId ?? persona.id.replace(/-r\d+$/, ""),
          replicate: persona.replicate ?? 1,
          difficulty: persona.difficulty ?? "junior3",
          turns: native.turns ?? [],
          characterCards: native.characterCards ?? [],
          startingCredits: native.startingCredits ?? null,
          endingCredits: native.endingCredits ?? null,
          persona: persona.label,
          plan: persona.plan,
          plannedTurns: persona.turnCount,
          completedTurns: native.completedTurns,
          activeMinutesEstimate: persona.activeMinutesEstimate,
          activeDaysPerMonthAssumption: persona.activeDaysPerMonthAssumption,
          nativeStatus: native.status,
          status:
            native.status === "running" &&
            annotations.environmentInterruptedIds.includes(persona.id)
              ? "environment_interrupted"
              : native.status,
          actions: native.actions,
          nativeCalls: native.calls ?? [],
          ledger,
        });
      }
      const summaries = sessions.map(summarizeSession);
      const [unattributed] = await database.sql<
        { calls: number; settledNanoyuan: string; unknownCalls: number }[]
      >`
        select count(*)::int as calls,coalesce(sum(settled_units),0)::text as "settledNanoyuan",
        count(*) filter(where status in ('reserved','dispatched','pending'))::int as "unknownCalls"
        from app.credit_operations where not (user_id=any(${manifest.cases.map((c) => c.userId)}::uuid[]))`;
      const report = {
        runId: manifest.runId,
        scenarioHash: manifest.scenarioHash,
        generatedAt: new Date().toISOString(),
        channelRate: 0.15,
        unattributed,
        sessions: summaries,
        rawSessions: sessions,
        annotations,
        sensitivity: summaries
          .filter((s) => s.projectedMonthlyCny !== null)
          .flatMap((s) =>
            [29, 39, 59, 79].flatMap((price) =>
              [0, 3, 10].map((freeRatio) => ({
                persona: s.id,
                ...pricingSensitivity(
                  s.projectedMonthlyCny ?? 0,
                  price,
                  freeRatio,
                  3,
                  5,
                ),
              })),
            ),
          ),
      };
      await writeFile(
        resolve(directory, "report.json"),
        JSON.stringify(report, null, 2),
      );
      const lines = [
        "# 真实使用成本试验",
        `Run: ${manifest.runId}`,
        "",
        "渠道抽成 15%。费用为真实供应商用量结算；时长与月活跃天数为场景假设。中断样本不外推月费。",
        "",
        "| 用户类型 | 完成轮次 | 状态 | 实测模型费用 | 调用数 | 辅助费用 | 未结算调用 | 假设月成本 |",
        "|---|---:|---|---:|---:|---:|---:|---:|",
        ...summaries.map(
          (s) =>
            `| ${s.persona} | ${String(s.completedTurns)}/${String(s.plannedTurns)} | ${s.status} | ¥${s.measuredCostCny.toFixed(6)} | ${String(s.calls)} | ¥${s.auxiliaryCostCny.toFixed(6)} | ${String(s.unknownCalls)} | ${s.projectedMonthlyCny === null ? "不可外推" : "¥" + s.projectedMonthlyCny.toFixed(2)} |`,
        ),
        "",
        "这是按场景与重复次数运行的合成用户会话试验，不是付费意愿或真实人群分布；不能据此声称 P95 用户月成本或确定售价。",
        "聊天耗时包含回复、辅助任务排空与至少 2 秒静默等待，不是首 token 延迟或纯界面响应耗时。",
        "敏感性表见 report.json：其他运营成本 ¥5/付费用户/月、免费成本 ¥3/免费用户/月均为假设。",
        "覆盖：实际 ChatViewModel、PromptBuilder、SwiftData、关系/纠错、记忆、测验、翻译、语法、角色生成、HTTP 网关、供应商、PostgreSQL 积分账本。",
        "边界：不包含触摸导航、麦克风识别/音频质量、公共 NPC 分配/头像、真实跨日恢复、外出概率分布及共享词典后台任务；语音从真实转写文本入口起测，返回用户重建 ViewModel 保留本次 SwiftData。",
      ];
      await writeFile(resolve(directory, "report.md"), lines.join("\n") + "\n");
      process.stdout.write(
        summaries
          .map(
            (s) =>
              `${s.id}: ${String(s.completedTurns)}/${String(s.plannedTurns)}, ¥${s.measuredCostCny.toFixed(6)}, ${s.status}, unknown=${String(s.unknownCalls)}`,
          )
          .join("\n") + "\n",
      );
    } else throw new Error("Expected prepare or report");
  } finally {
    await database.close();
  }
}
void main().catch((e: unknown) => {
  process.stderr.write(`${e instanceof Error ? e.message : "Evaluation failed"}\n`);
  process.exitCode = 1;
});
