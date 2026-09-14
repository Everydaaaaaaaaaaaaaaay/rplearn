import PersistenceKit
import BackendKit
import BillingKit
import SwiftUI

public struct UsageAccessView: View {
    let backend: BackendClient
    let billing: BillingController
    @State private var snapshot: BackendAccessSnapshot?
    @State private var error: String?

    public init(backend: BackendClient, billing: BillingController) {
        self.backend = backend
        self.billing = billing
    }
    public var body: some View {
        List {
            if let snapshot {
                Section {
                    LabeledContent("方案", value: billing.tier.displayName)
                    LabeledContent("普通好友位", value: "\(snapshot.policy.friendSlotLimit)")
                    Text("剧情旅伴不占好友位。已有好友、聊天和旅行成果会保留。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let credits = snapshot.credits {
                    Section("AI 积分余额") {
                        LabeledContent("可用积分", value: points(credits.remaining))
                        LabeledContent("本期额度", value: points(credits.limit))
                        Text("积分用于云端 AI 功能；金币用于购买机票，两者独立。")
                            .font(.footnote).foregroundStyle(.secondary)
                        LabeledContent("已消耗", value: points(credits.used))
                        Text(resetDescription(snapshot)).font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("最近消耗") {
                        if credits.recent.isEmpty {
                            Text("暂无消耗记录").foregroundStyle(.secondary)
                        }
                        ForEach(credits.recent) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                LabeledContent(taskName(entry.task), value: entry.credits.map { "\(points($0)) 积分" } ?? (entry.status == "released" ? "未扣费" : "用量核对中 · 未扣费"))
                                Text(entryDate(entry.createdAt)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        DisclosureGroup("积分如何使用") {
                            Text("发送消息、生成角色及主动发起的云端讲解和翻译，按实际用量消耗积分。")
                            Text("自动关系理解、学习建议、旅伴记忆和主动问候不扣用户积分。设备上的语音识别、朗读、本地查词与 Apple 整句翻译同样不扣积分。")
                            Text("用量核对中的请求不占用额度。积分用完后暂停新的云端操作；已开始的操作可以完成。")
                        }.font(.footnote)
                    }
                } else {
                    Section("剩余额度") {
                        Text("当前服务尚未返回积分余额与明细。请稍后重试。")
                        balance("chat", title: "聊天与邂逅", unit: "次", snapshot: snapshot)
                        balance("voice", title: "实时语音", unit: "秒", snapshot: snapshot)
                        balance("advanced", title: "语法、单词与语音解析", unit: "次", snapshot: snapshot)
                        Text(resetDescription(snapshot)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if snapshot.policy.provisional {
                    Section { Text("额度处于试行阶段，会结合实际使用成本调整。购买前请以商品页说明为准。")
                        .font(.footnote).foregroundStyle(.secondary) }
                }
            } else if error == nil { ProgressView("正在读取用量…") }
            if let error {
                Section("积分加载失败") { Text(error); Button("重试") { Task { await reload() } } }
            }
            if FileManager.default.fileExists(atPath: ContentSyncStore.guestArchiveURL.path) {
                Section("旧版本旅程备份") {
                    ShareLink("导出迁移前的本地记录", item: ContentSyncStore.guestArchiveURL)
                    Text("备份保留旧版金币、机票、角色和学习记录。可用资产按服务器确认的奖励恢复，开发期赠送额度不会重新启用。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

        }
        .navigationTitle("积分余额与明细")
        .task { await reload() }
        .refreshable { await reload() }
    }
    private func points(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }
    private func taskName(_ task: String) -> String {
        switch task {
        case "conversation": "聊天回复"
        case "coach_review": "学习建议与关系理解"
        case "memory_summary": "旅伴记忆整理"
        case "quiz": "情境小测"
        case "translation": "整句翻译"
        case "character_generation": "生成新角色"
        case "grammar_explain": "语法讲解"
        case "dictionary_explain": "单词讲解"
        case "speech_feedback": "语音反馈"
        case "dictionary_example_translation": "例句翻译"
        default: "学习辅助"
        }
    }
    private func balance(_ key: String, title: String, unit: String, snapshot: BackendAccessSnapshot) -> some View {
        Group {
            if let item = snapshot.balances[key] {
                LabeledContent(title, value: "\(item.remaining) / \(item.limit) \(unit)")
                if item.reserved > 0 {
                    Text("正在使用：\(item.reserved) \(unit)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func resetDescription(_ snapshot: BackendAccessSnapshot) -> String {
        guard let date = snapshot.credits?.resetsAt ?? snapshot.resetsAt else { return "一次性体验额度，不会自动恢复。" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let parsed = formatter.date(from: date) ?? ISO8601DateFormatter().date(from: date) else { return "按服务器时间恢复额度。" }
        return "下次恢复：\(parsed.formatted(date: .abbreviated, time: .shortened))。未用完的额度不累计。"
    }
    private func entryDate(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    private func reload() async {
        do { snapshot = try await backend.accessSnapshot(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
