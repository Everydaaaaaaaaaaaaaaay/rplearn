import BackendKit
import DesignSystem
import SwiftUI

struct AppointmentSummaryView: View {
    @Bindable var model: AppointmentModel
    let characterName: (UUID) -> String
    let onChat: (UUID) -> Void
    let onMemory: (UUID) -> Void
    @State private var history = false
    private let ink = AppointmentStyle.ink

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let item = model.detail?.appointment {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(item.displayCityName).font(.caption.weight(.semibold)).foregroundStyle(ink.opacity(0.65))
                        Text(item.displayTitle(companionName: characterName(item.characterId)))
                            .font(.largeTitle.weight(.semibold))
                        Text(AppointmentTime.formatted(item.startsAt, timeZone: item.timeZone))
                            .font(.subheadline).foregroundStyle(ink.opacity(0.65))
                        if let summary = model.detail?.summary {
                            Divider()
                            Text(summary.reflection).font(.system(.title3, design: .serif))
                                .lineSpacing(6).textSelection(.enabled)
                        }
                    }
                    .padding(24).frame(maxWidth: .infinity, alignment: .leading).appointmentSurface()
                    if let summary = model.detail?.summary {
                        relationship(summary)
                        actualPath
                        memories(summary, characterID: item.characterId)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("回顾整理中").font(.headline)
                            Text("经历已保存，可以稍后查看。").font(.subheadline).foregroundStyle(ink.opacity(0.65))
                            Button("重新载入回顾") { Task { await model.load() } }.frame(minHeight: 44)
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).appointmentSurface()
                        actualPath
                    }
                    if let error = model.error { Text(error).font(.footnote) }
                    Button { history = true } label: {
                        HStack { Text("回看完整经历"); Spacer(); Image(systemName: "arrow.up.right") }
                            .font(.subheadline.weight(.semibold)).padding(24).frame(minHeight: 52)
                            .appointmentSurface()
                    }.buttonStyle(DSSceneEntranceButtonStyle())
                }
            }
            .padding(22).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .appointmentChrome(cityID: model.detail?.appointment.cityId ?? "", cityName: model.detail?.appointment.displayCityName ?? "")
        .navigationTitle("赴约回顾").navigationBarTitleDisplayMode(.inline).navigationBarHidden(false).dsTabBarHidden()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let item = model.detail?.appointment {
                Button { onChat(item.characterId) } label: {
                    Label("返回聊天", systemImage: "bubble.left")
                }
                .buttonStyle(AppointmentPrimaryButtonStyle())
                .padding(.horizontal, 22).padding(.vertical, 12)
                .background(.regularMaterial)
                .accessibilityIdentifier("appointment.backToChat")
            }
        }
        .sheet(isPresented: $history) { AppointmentHistoryView(detail: model.detail, characterName: characterName) }
        .task { await model.settleIfPending() }
    }

    private func relationship(_ summary: BackendAppointmentSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("好感度").font(.headline)
            if summary.affinity.status == "settled", let before = summary.affinity.before, let after = summary.affinity.after, let delta = summary.affinity.delta {
                Text(affinityLabel(delta)).font(.title.weight(.semibold)).accessibilityIdentifier("appointment.affinity")
                Text("\(number(before)) → \(number(after))").font(.subheadline).monospacedDigit().foregroundStyle(ink.opacity(0.65))
            } else {
                Text("待结算").font(.title2.weight(.semibold)).accessibilityIdentifier("appointment.affinity.pending")
                Text("经历已保存，关系评价完成后会显示实际变化。").font(.subheadline)
                Button(model.settling ? "正在整理…" : "重试整理回顾") {
                    Task { await model.settleIfPending(); await model.load() }
                }.disabled(model.settling || model.loading || model.offline).frame(minHeight: 44)
            }
            Text(summary.affinity.reason).font(.subheadline).foregroundStyle(ink.opacity(0.65))
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading).appointmentSurface()
    }

    private func memories(_ summary: BackendAppointmentSummary, characterID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("共同记忆").font(.headline)
            if summary.memories.isEmpty {
                Text(summary.affinity.status == "pending" ? "记忆整理中。" : "这次没有新增精选记忆，完整经历可随时回看。")
                    .font(.subheadline).foregroundStyle(ink.opacity(0.65))
            }
            ForEach(summary.memories) { memory in
                VStack(alignment: .leading, spacing: 8) {
                    Text(memory.content).font(.body).lineSpacing(4)
                    Text(memoryStatus(memory.status)).font(.caption).foregroundStyle(ink.opacity(0.6))
                }
            }
            Button { onMemory(characterID) } label: {
                HStack { Text("管理记忆"); Spacer(); Image(systemName: "arrow.up.right") }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }.accessibilityIdentifier("appointment.manageMemories")
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading).appointmentSurface()
    }

    private var actualPath: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("你的选择").font(.headline)
            if model.detail?.session?.decisions.isEmpty != false {
                Text("这次没有提交选择。").font(.subheadline).foregroundStyle(ink.opacity(0.65))
            }
            ForEach(model.detail?.session?.decisions ?? []) { decision in
                VStack(alignment: .leading, spacing: 10) {
                    if let block = model.blocks.first(where: { $0.id == decision.blockId }) {
                        Text(block.location).font(.caption).foregroundStyle(ink.opacity(0.6))
                    }
                    Text(decision.input).font(.body.weight(.medium)).textSelection(.enabled)
                    if decision.custom { Text("自定义行动").font(.caption).foregroundStyle(ink.opacity(0.6)) }
                    Text(decision.outcome).font(.subheadline).foregroundStyle(ink.opacity(0.7)).textSelection(.enabled)
                }
                .padding(.leading, 16)
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(ink.opacity(0.15)).frame(width: 2) }
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading).appointmentSurface()
        .accessibilityIdentifier("appointment.actualPath")
    }

    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...3))) }
    private func affinityLabel(_ delta: Double) -> String {
        if delta == 0 { return "好感不变" }
        if abs(delta) < 0.1 { return delta > 0 ? "好感略有增加" : "好感略有降低" }
        return "好感 \(delta > 0 ? "+" : "")\(number(delta))"
    }
    private func memoryStatus(_ value: String) -> String {
        switch value {
        case "active", "saved": "已保存 · 可管理"
        case "forgotten", "deleted": "已遗忘 · 不再用于聊天"
        case "superseded": "已更新"
        case "edited": "已纠正 · 可管理"
        case "archived": "已归档"
        case "unavailable": "状态暂不可用"
        case "pending": "待保存"
        default: "状态：\(value)"
        }
    }
}

struct AppointmentHistoryView: View {
    let detail: BackendAppointmentDetail?
    let characterName: (UUID) -> String
    @Environment(\.dismiss) private var dismiss
    private let ink = AppointmentStyle.ink

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let item = detail?.appointment {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.displayTitle(companionName: characterName(item.characterId)))
                                .font(.title2.weight(.semibold))
                            Text("\(item.displayCityName) · \(AppointmentTime.formatted(item.startsAt, timeZone: item.timeZone))")
                                .font(.caption).foregroundStyle(ink.opacity(0.65))
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).appointmentSurface()
                    }
                    ForEach(detail?.session?.blocks.sorted { $0.sequence < $1.sequence } ?? []) { block in
                        VStack(alignment: .leading, spacing: 22) {
                            Text(block.location).font(.subheadline.weight(.semibold)).foregroundStyle(ink.opacity(0.65))
                            ForEach(Array(block.beats.enumerated()), id: \.offset) { _, beat in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(beat.speaker == "character" ? detail.map { characterName($0.appointment.characterId) } ?? "旅伴" : "旁白")
                                        .font(.caption.weight(.semibold)).foregroundStyle(ink.opacity(0.6))
                                    Text(beat.english).font(.system(.body, design: .serif)).lineSpacing(6).textSelection(.enabled)
                                    Text(beat.chinese).font(.subheadline).foregroundStyle(ink.opacity(0.7)).textSelection(.enabled)
                                }
                            }
                            ForEach(detail?.session?.decisions.filter { $0.blockId == block.id } ?? []) { decision in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(decision.custom ? "你 · 自定义行动" : "你的选择").font(.caption.weight(.semibold))
                                    Text(decision.input).textSelection(.enabled)
                                    Text(decision.outcome).font(.subheadline).foregroundStyle(ink.opacity(0.7))
                                }
                                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                            }
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).appointmentSurface()
                    }
                }.padding(22).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .appointmentChrome(cityID: detail?.appointment.cityId ?? "", cityName: detail?.appointment.displayCityName ?? "")
            .navigationTitle("实际经历").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .tint(ink)
    }
}
