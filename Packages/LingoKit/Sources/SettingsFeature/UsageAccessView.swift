import PersistenceKit
import BackendKit
import BillingKit
import SwiftUI

public struct UsageAccessView: View {
    let backend: BackendClient
    let billing: BillingController
    let onSignIn: @MainActor () -> Void
    @State private var snapshot: BackendAccessSnapshot?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    public init(backend: BackendClient, billing: BillingController, onSignIn: @escaping @MainActor () -> Void) {
        self.backend = backend
        self.billing = billing
        self.onSignIn = onSignIn
    }
    public var body: some View {
        NavigationStack {
            List {
                if let snapshot {
                    Section {
                        LabeledContent("身份", value: snapshot.policy.isGuest ? "游客" : billing.tier.displayName)
                        LabeledContent("普通好友位", value: "\(snapshot.policy.friendSlotLimit)")
                        Text("剧情旅伴不占好友位。已有好友、聊天和旅行成果会保留。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("剩余额度") {
                        balance("chat", title: "聊天与邂逅", unit: "次", snapshot: snapshot)
                        balance("voice", title: "实时语音", unit: "秒", snapshot: snapshot)
                        balance("advanced", title: "专项解析", unit: "次", snapshot: snapshot)
                        Text(resetDescription(snapshot)).font(.footnote).foregroundStyle(.secondary)
                        Text("专项解析包括语法解析、单词讲解和语音反馈。自动记忆与纠错不会额外扣聊天次数。语音按会话时长计量，识别和朗读在设备上完成。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if snapshot.policy.isGuest {
                        Section {
                            Button("登录，获得每日额度") { dismiss(); onSignIn() }
                            Text("游客额度为一次性体验，不会自动恢复。登录后可继续剧情并飞往其他城市。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
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
