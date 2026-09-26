import { ZodError } from "zod";
import { AppError } from "../../shared/errors.js";
import type {
  LearningAdminRepository,
  LearningAdminFilter,
} from "./admin-repository.js";
import type { LearningGenerationRepository } from "./generation-repository.js";
import type { GenerationBlueprint } from "./generation-content.js";
import { contentHash, unitSchema, type LearningUnit } from "./content.js";

function operatorLabel(key: string) {
  return `管理员 ${key.length <= 54 ? key : `${key.slice(0, 35)}…${contentHash(key).slice(0, 12)}`}`;
}
export class LearningAdminService {
  constructor(
    private readonly repository: LearningAdminRepository,
    private readonly generation: LearningGenerationRepository,
    private readonly blueprints: readonly GenerationBlueprint[],
  ) {}
  units(filter: LearningAdminFilter) {
    return this.repository.units(filter);
  }
  jobs(filter: LearningAdminFilter) {
    return this.repository.jobs(filter);
  }
  async unit(id: string, version?: number) {
    const found = await this.repository.unit(id, version);
    if (!found)
      throw new AppError({
        code: "LEARNING_UNIT_NOT_FOUND",
        message: "找不到这个单元版本。",
        statusCode: 404,
      });
    return found;
  }
  async job(id: string) {
    const job = await this.generation.inspect(id);
    const parsed = unitSchema.safeParse(job.candidate);
    const blueprint = this.blueprints.find(
      (b) => b.roleKey === job.role_key && b.level === job.level_key,
    );
    return {
      ...job,
      editableUnit: parsed.success ? parsed.data : null,
      previewUnit: parsed.success
        ? parsed.data
        : await this.repository.revisionDraft(id),
      canRevise:
        parsed.success &&
        Boolean(blueprint) &&
        job.blueprint_hash === blueprint?.hash &&
        ["failed", "review", "pending"].includes(job.status) &&
        !job.edits.some((e) => e.source_job_id === id),
      isRevision: job.edits.some((e) => e.revised_job_id === id),
      blueprintAvailable: Boolean(blueprint),
      allowedGoalIds: blueprint?.goalIds ?? [],
    };
  }
  private async blueprint(id: string) {
    const job = await this.generation.inspect(id);
    const blueprint = this.blueprints.find(
      (b) => b.roleKey === job.role_key && b.level === job.level_key,
    );
    if (!blueprint)
      throw new AppError({
        code: "LEARNING_BLUEPRINT_UNAVAILABLE",
        message: "该角色和水平尚无已核读的内容蓝图，暂不能修订或发布。",
        statusCode: 409,
      });
    return blueprint;
  }
  async revise(
    id: string,
    input: {
      requestId: string;
      candidateHash: string;
      notes: string;
      unit: LearningUnit;
    },
    operator: string,
  ) {
    const blueprint = await this.blueprint(id);
    try {
      const revisedJobId = await this.generation.revise(
        { ...input, sourceJobId: id, editor: operatorLabel(operator) },
        blueprint,
      );
      return { revisedJobId };
    } catch (error) {
      if (error instanceof ZodError)
        throw new AppError({
          code: "LEARNING_CONTENT_INVALID",
          message: "稿件结构或答案配置不完整，请检查每道题。",
          statusCode: 422,
        });
      throw error;
    }
  }
  async publish(id: string, hash: string, notes: string, operator: string) {
    await this.generation.publish(
      id,
      hash,
      await this.blueprint(id),
      operatorLabel(operator),
      notes,
    );
    return { status: "published" };
  }
  async reject(id: string, hash: string, notes: string, operator: string) {
    await this.generation.reject(id, hash, notes, operatorLabel(operator));
    return { status: "failed" };
  }
}
