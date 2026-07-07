/// 按任务开销/智力需求划分的模型档位。
/// 任务矩阵见 plan.md §4：角色扮演=balanced、教练纠错/记忆压缩=fast、等。
public enum LLMTier: String, Sendable, CaseIterable, Codable {
    case fast
    case balanced
    case deep
}
