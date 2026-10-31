import BackendKit
import DesignSystem
import SwiftUI

struct AppointmentSummaryView: View {
    @Bindable var model: AppointmentModel
    let characterName: (UUID) -> String
    let onChat: (UUID) -> Void
    let onMemory: (UUID) -> Void
    @State private var history = false
    private let paper = Color(red: 0.98, green: 0.96, blue: 0.90)
    private let ink = Color(red: 0.13, green: 0.19, blue: 0.18)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let item = model.detail?.appointment {
                    AppointmentPhotoView(cityID: item.cityId, cityName: item.cityName, paused: true).frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(model.detail?.summary?.title ?? item.title).font(.largeTitle.weight(.medium)).fontDesign(.serif)
                    Text("与 \(characterName(item.characterId)) · \(item.cityName)\n\(AppointmentTime.formatted(item.startsAt, timeZone: item.timeZone))").font(.subheadline).foregroundStyle(.secondary)
                    if let summary = model.detail?.summary {
                        Text(summary.reflection).font(.title3).fontDesign(.serif).textSelection(.enabled)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("这次相处的关系变化").font(.headline)
                            if summary.affinity.status == "settled", let before = summary.affinity.before, let after = summary.affinity.after, let delta = summary.affinity.delta {
                                Text(affinityLabel(delta)).font(.title2.weight(.medium)).accessibilityIdentifier("appointment.affinity")
                                Text("\(number(before)) → \(number(after))").font(.subheadline)
                            } else {
                                Text("待结算").font(.title2.weight(.medium)).accessibilityIdentifier("appointment.affinity.pending")
                                Text("经历已经保存。关系评价完成后，这里会显示本次事件的实际变化。").font(.subheadline)
                                Button(model.settling ? "正在整理…" : "重试整理回顾") { Task { await model.settleIfPending(); await model.load() } }.disabled(model.settling || model.loading || model.offline)
                            }
                            Text(summary.affinity.reason).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Divider()
                        actualPath
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("留下的共同经历").font(.headline)
                            if summary.memories.isEmpty {
                                Text(summary.affinity.status == "pending" ? "记忆仍在整理，暂未确认保存。" : "这次没有新增精选记忆。实际经历仍可回看。").font(.subheadline).foregroundStyle(.secondary)
                            }
                            ForEach(summary.memories) { memory in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(memory.content)
                                    Text(memoryStatus(memory.status)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Button("管理这位旅伴的记忆") { onMemory(item.characterId) }.frame(minHeight: 44).accessibilityIdentifier("appointment.manageMemories")
                        }
                    } else {
                        Text("经历已保存，回顾仍在整理。").font(.headline)
                        Button("重新载入回顾") { Task { await model.load() } }
                        actualPath
                    }
                    if let error = model.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    Button("回看完整经历") { history = true }.frame(minHeight: 44)
                }
            }.padding(20)
        }
        .background(paper.ignoresSafeArea())
        .foregroundStyle(ink)
        .navigationTitle("这次相处").navigationBarTitleDisplayMode(.inline).navigationBarHidden(false).dsTabBarHidden()
        .toolbarBackground(paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if let item = model.detail?.appointment {
                Button { onChat(item.characterId) } label: { Label("返回聊天", systemImage: "bubble.left").frame(maxWidth: .infinity, minHeight: 48) }.buttonStyle(.borderedProminent).padding().background(paper).accessibilityIdentifier("appointment.backToChat")
            }
        }
        .sheet(isPresented: $history) { AppointmentHistoryView(detail: model.detail, characterName: characterName) }
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .task { await model.settleIfPending() }
    }

    private var actualPath: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("你实际留下的选择").font(.headline)
            if model.detail?.session?.decisions.isEmpty != false { Text("这次没有提交选择。").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(model.detail?.session?.decisions ?? []) { decision in
                VStack(alignment: .leading, spacing: 8) {
                    if let block = model.blocks.first(where: { $0.id == decision.blockId }) { Text(block.location).font(.caption).foregroundStyle(.secondary) }
                    Text(decision.input).font(.body.weight(.medium)).textSelection(.enabled)
                    if decision.custom { Text("自己说的").font(.caption).foregroundStyle(.secondary) }
                    Text(decision.outcome).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }.accessibilityIdentifier("appointment.actualPath")
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
    private let paper = Color(red: 0.98, green: 0.96, blue: 0.90)
    private let ink = Color(red: 0.13, green: 0.19, blue: 0.18)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    Text("这里只记录已经接受的故事和你的真实回应。").font(.footnote).foregroundStyle(.secondary)
                    ForEach(detail?.session?.blocks.sorted { $0.sequence < $1.sequence } ?? []) { block in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(block.location).font(.headline)
                            ForEach(Array(block.beats.enumerated()), id: \.offset) { _, beat in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(beat.speaker == "character" ? detail.map { characterName($0.appointment.characterId) } ?? "旅伴" : "旁白").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    Text(beat.english).textSelection(.enabled)
                                    Text(beat.chinese).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            ForEach(detail?.session?.decisions.filter { $0.blockId == block.id } ?? []) { decision in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(decision.custom ? "你 · 自己说的" : "你的选择").font(.caption.weight(.semibold))
                                    Text(decision.input)
                                    Text(decision.outcome).font(.subheadline).foregroundStyle(.secondary)
                                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }
                            Divider()
                        }
                    }
                }.padding(20)
            }
                .background(paper.ignoresSafeArea())
                .foregroundStyle(ink)
                .navigationTitle("实际经历").navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(paper, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.light, for: .navigationBar)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .presentationBackground(paper)
    }
}
