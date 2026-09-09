import PersistenceKit
import BackendKit
import BillingKit
import SwiftUI

public struct UsageAccessView: View {
    let backend: BackendClient
    let billing: BillingController
    @State private var snapshot: BackendAccessSnapshot?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    public init(backend: BackendClient, billing: BillingController) {
        self.backend = backend
        self.billing = billing
    }
    public var body: some View {
        NavigationStack {
            List {
                if let snapshot {
                    Section {
                        LabeledContent("方案", value: billing.tier.displayName)
                        LabeledContent("普通好友位", value: "\(snapshot.policy.friendSlotLimit)")
                        Text("剧情旅伴不占好友位。已有好友、聊天和旅行成果会保留。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let credits = snapshot.credits {
                        Section("模型积分") {
                            LabeledContent("可用积分", value: "\(points(credits.remaining)) / \(points(credits.limit))")
                            LabeledContent("已消耗", value: points(credits.used))
                            if credits.reserved > 0 { LabeledContent("请求预留", value: points(credits.reserved)) }
                            if credits.pending > 0 {
                                LabeledContent("待核对预留", value: points(credits.pending))
                                Text("部分调用尚未取得完整用量，暂时保留预留积分；核对后按实际费用结算。")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Text(resetDescription(snapshot)).font(.footnote).foregroundStyle(.secondary)
                            Text("聊天、生成新角色、语法与单词讲解，以及自动记忆、纠错等模型调用，共用积分。按实际输入、缓存输入和输出消耗结算，未使用的预留会返还。设备上的语音识别、朗读和本地查词不扣模型积分。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if !credits.recent.isEmpty {
                            Section("最近消耗") {
                                ForEach(credits.recent) { entry in
                                    LabeledContent(taskName(entry.task), value: entry.credits.map { "\(points($0)) 积分" } ?? (entry.status == "released" ? "未发出 · 已释放" : "预留 \(points(entry.heldCredits)) · \(entry.status == "pending" ? "待核对" : "处理中")"))
                                }
                            }
                        }
                    } else {
                        Section("剩余额度") {
                            balance("chat", title: "聊天与邂逅", unit: "次", snapshot: snapshot)
                            balance("voice", title: "实时语音", unit: "秒", snapshot: snapshot)
                            balance("advanced", title: "语法、单词与语音解析", unit: "次", snapshot: snapshot)
                            Text(resetDescription(snapshot)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section("订阅方案") {
                        if billing.offeredProducts.isEmpty {
                            Text("当前暂无可购买商品，请稍后在账号页查看。")
                        }
                        ForEach(billing.offeredProducts) { product in
                            Button {
                                Task { await billing.purchase(product); await reload() }
                            } label: {
                                LabeledContent(product.tier.displayName, value: product.displayPrice)
                            }.disabled(billing.operation != .idle)
                        }
                        Button("恢复购买") { Task { await billing.restorePurchases(); await reload() } }
                    }
                    if snapshot.policy.provisional {
                        Section { Text("额度处于试行阶段，会结合实际使用成本调整。购买前请以商品页说明为准。")
                            .font(.footnote).foregroundStyle(.secondary) }
                    }
                } else if error == nil { ProgressView("正在读取用量…") }
                if FileManager.default.fileExists(atPath: ContentSyncStore.guestArchiveURL.path) {
                    Section("旧版本旅程备份") {
                        ShareLink("导出迁移前的本地记录", item: ContentSyncStore.guestArchiveURL)
                        Text("备份保留旧版金币、机票、角色和学习记录。可用资产按服务器确认的奖励恢复，开发期赠送额度不会重新启用。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Section { Text(error); Button("重试") { Task { await reload() } } }
                }
            }
            .navigationTitle("用量与权益")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }
    private func points(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...6)))
    }
    private func taskName(_ task: String) -> String {
        switch task {
        case "conversation": "聊天回复"
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
        guard let date = snapshot.resetsAt else { return "一次性体验额度，不会自动恢复。" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let parsed = formatter.date(from: date) else { return "按服务器时间恢复额度。" }
        return "下次恢复：\(parsed.formatted(date: .abbreviated, time: .shortened))。未用完的额度不累计。"
    }
    private func reload() async {
        do { snapshot = try await backend.accessSnapshot(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
