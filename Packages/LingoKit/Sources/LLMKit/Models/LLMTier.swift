/// 按任务开销/智力需求划分的模型档位。
/// 模型能力分档：角色扮演使用 balanced，教练纠错与记忆压缩使用 fast。
public enum LLMTier: String, Sendable, CaseIterable, Codable {
    case fast
    case balanced
    case deep
}
