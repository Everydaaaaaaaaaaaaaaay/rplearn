import BackendKit
import DesignSystem
import SwiftUI

struct AppointmentSummaryView: View {
    @Bindable var model: AppointmentModel
    let characterName: (UUID) -> String
    let onChat: (UUID) -> Void
    let onMemory: (UUID) -> Void
    var onBack: (() -> Void)? = nil
    @State private var history = false
    @ScaledMetric(relativeTo: .body) private var bodySize = 16
    @ScaledMetric(relativeTo: .subheadline) private var secondarySize = 14
    @ScaledMetric(relativeTo: .headline) private var affinitySize = 18
    private let ink = AppointmentStyle.ink

    var body: some View {
        AppointmentPage(cityID: model.detail?.appointment.cityId ?? "", cityName: model.detail?.appointment.cityName ?? "",
                        title: "回顾", onBack: onBack) {
            ScrollView {
                if let item = model.detail?.appointment {
                    VStack(alignment: .leading, spacing: 0) {
                        AppointmentIdentityView(appointment: item, name: characterName(item.characterId))
                        AppointmentSectionDivider()
                        if let summary = model.detail?.summary {
                            relationship(summary)
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("回顾整理中").font(.headline)
                                Text("经历已保存，可以稍后查看。").font(.subheadline).foregroundStyle(ink.opacity(0.65))
                                Button("重新载入回顾") { Task { await model.load() } }.frame(minHeight: 44)
                            }
                        }
                        AppointmentSectionDivider()
                        actualPath
                        if let summary = model.detail?.summary {
                            AppointmentSectionDivider()
                            memories(summary, characterID: item.characterId)
                        }
                        if let error = model.error { Text(error).font(.footnote).padding(.top, 12) }
                        Button { history = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("回看完整经历")
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12))
                            }.font(.puff(.subheadline, Puff.Weight.emphasis)).frame(minHeight: 48)
                            .padding(.horizontal, 8)
                        }.buttonStyle(.puffRow).padding(.top, 12)
                        Button { onChat(item.characterId) } label: { Text("返回聊天") }
                            .buttonStyle(AppointmentPrimaryButtonStyle()).padding(.top, 12)
                            .accessibilityIdentifier("appointment.backToChat")
                    }
                    .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 24)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
                } else { PuffLoadingDots().padding(40).accessibilityLabel("正在打开回顾") }
            }.scrollBounceBehavior(.basedOnSize)
        }
        .dsInteractivePopGesture()
        .dsTabBarHidden()
        .sheet(isPresented: $history) { AppointmentHistoryView(detail: model.detail, characterName: characterName) }
        .task {
            if model.detail == nil { await model.load() }
            else { await model.settleIfPending() }
        }
    }

    private func relationship(_ summary: BackendAppointmentSummary) -> some View {
        HStack(alignment: .top, spacing: 14) {
            let candy: PuffCandy = summary.affinity.delta.map { $0 < 0 } == true ? .tangerine : .bubblegum
            Image(systemName: "heart.fill")
                .font(.system(size: 20, weight: Puff.Weight.icon)).foregroundStyle(candy.base)
                .frame(width: 38, height: 38).background(candy.wash, in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                if summary.affinity.status == "settled", let before = summary.affinity.before,
                   let after = summary.affinity.after, let delta = summary.affinity.delta {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(affinityLabel(delta)).font(.system(size: affinitySize, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("appointment.affinity")
                        Spacer(minLength: 0)
                        Text("\(number(before)) → \(number(after))")
                            .font(.caption).monospacedDigit().foregroundStyle(ink.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("好感待结算").font(.system(size: affinitySize, weight: .semibold))
                        .accessibilityIdentifier("appointment.affinity.pending")
                    Text("经历已保存，关系评价完成后会显示实际变化。").font(.footnote)
                    Button(model.settling ? "正在整理…" : "重试整理回顾") {
                        Task { await model.settleIfPending(); await model.load() }
                    }.disabled(model.settling || model.loading || model.offline).frame(minHeight: 44)
                }
                if !summary.affinity.reason.isEmpty {
                    Text(summary.affinity.reason).font(.footnote).foregroundStyle(ink.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func memories(_ summary: BackendAppointmentSummary, characterID: UUID) -> some View {
        let allSaved = !summary.memories.isEmpty && summary.memories.allSatisfy { ["active", "saved"].contains($0.status) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("共同记忆", systemImage: "bookmark").font(.system(size: bodySize, weight: .semibold))
                Spacer()
                if allSaved { Label("已保存", systemImage: "checkmark.circle").font(.caption).foregroundStyle(ink.opacity(0.6)) }
            }
            if summary.memories.isEmpty {
                Text(summary.affinity.status == "pending" ? "记忆整理中。" : "这次没有新增精选记忆，完整经历可随时回看。")
                    .font(.subheadline).foregroundStyle(ink.opacity(0.65))
            }
            ForEach(summary.memories) { memory in
                VStack(alignment: .leading, spacing: 8) {
                    Text(memory.content).font(.subheadline).lineSpacing(4)
                        .foregroundStyle(ink.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                    if !allSaved { Text(memoryStatus(memory.status)).font(.caption).foregroundStyle(ink.opacity(0.6)) }
                }
            }
            Button { onMemory(characterID) } label: {
                HStack(spacing: 6) {
                    Text("管理记忆")
                    Image(systemName: "arrow.up.right").font(.system(size: 11))
                }.font(.footnote.weight(.medium)).frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityIdentifier("appointment.manageMemories")
        }
    }

    private var actualPath: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("你的选择", systemImage: "arrow.turn.down.right").font(.system(size: bodySize, weight: .semibold))
            if model.detail?.session?.decisions.isEmpty != false {
                Text("这次没有提交选择。").font(.subheadline).foregroundStyle(ink.opacity(0.65))
            }
            ForEach(model.detail?.session?.decisions ?? []) { decision in
                HStack(alignment: .top, spacing: 12) {
                    UserAvatar(name: "你", size: 26)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(decision.input).font(.system(size: bodySize, weight: .medium)).lineSpacing(3).textSelection(.enabled)
                        Text(decision.outcome).font(.system(size: secondarySize)).lineSpacing(3)
                            .foregroundStyle(ink.opacity(0.65)).textSelection(.enabled)
                    }.fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...3))) }
    private func affinityLabel(_ delta: Double) -> String {
        if delta == 0 { return "好感不变" }
        if abs(delta) < 0.1 { return delta > 0 ? "好感略有增加" : "好感略有降低" }
        return "好感 \(delta > 0 ? "+" : "")\(number(delta))"
    }
    private func memoryStatus(_ value: String) -> String {
        switch value {
        case "active", "saved": "已保存"
        case "forgotten", "deleted": "已遗忘 · 不再用于聊天"
        case "superseded": "已更新"
        case "edited": "已纠正"
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
    @ScaledMetric(relativeTo: .body) private var bodySize = 16
    @ScaledMetric(relativeTo: .subheadline) private var secondarySize = 14
    private let ink = AppointmentStyle.ink
    private var blocks: [BackendAppointmentBlock] { detail?.session?.blocks.sorted { $0.sequence < $1.sequence } ?? [] }

    var body: some View {
        NavigationStack {
            AppointmentPage(cityID: detail?.appointment.cityId ?? "", cityName: detail?.appointment.cityName ?? "",
                            title: "实际经历", backLabel: "返回阅读") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let item = detail?.appointment {
                            AppointmentIdentityView(appointment: item, name: characterName(item.characterId))
                            AppointmentSectionDivider()
                        }
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                            VStack(alignment: .leading, spacing: 20) {
                                if index == 0 || blocks[index - 1].location != block.location {
                                    Label(block.location, systemImage: "mappin").font(.footnote).foregroundStyle(ink.opacity(0.65))
                                }
                                ForEach(Array(block.beats.enumerated()), id: \.offset) { _, beat in
                                    HStack(alignment: .top, spacing: 12) {
                                        if beat.speaker == "character", let item = detail?.appointment {
                                            AppointmentAvatarView(characterID: item.characterId, name: characterName(item.characterId))
                                        }
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(beat.speaker == "character" ? detail.map { characterName($0.appointment.characterId) } ?? "旅伴" : "旁白")
                                                .font(.caption.weight(.medium)).foregroundStyle(ink.opacity(0.6))
                                            Text(beat.english).font(.system(size: bodySize)).lineSpacing(5).textSelection(.enabled)
                                            Text(beat.chinese).font(.system(size: secondarySize)).lineSpacing(4)
                                                .foregroundStyle(ink.opacity(0.65)).textSelection(.enabled)
                                        }
                                    }.fixedSize(horizontal: false, vertical: true)
                                }
                                ForEach(detail?.session?.decisions.filter { $0.blockId == block.id } ?? []) { decision in
                                    HStack(alignment: .top, spacing: 12) {
                                        UserAvatar(name: "你", size: 26)
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(decision.custom ? "你 · 自定义行动" : "你的选择").font(.caption.weight(.medium))
                                                .foregroundStyle(ink.opacity(0.6))
                                            Text(decision.input).font(.system(size: bodySize, weight: .medium)).textSelection(.enabled)
                                            Text(decision.outcome).font(.system(size: secondarySize)).foregroundStyle(ink.opacity(0.65))
                                        }
                                    }.fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            AppointmentSectionDivider()
                        }
                    }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 24)
                        .frame(maxWidth: 640).frame(maxWidth: .infinity)
                }.scrollBounceBehavior(.basedOnSize)
            }
        }.tint(ink)
    }
}
