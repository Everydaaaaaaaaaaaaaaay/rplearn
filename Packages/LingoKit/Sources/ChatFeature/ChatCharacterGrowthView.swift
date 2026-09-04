import DesignSystem
import Foundation
import Observation
import PersistenceKit
import SwiftUI

/// 用户可审阅并控制当前关系分支中的 NPC 成长，不修改公共身份或稳定人格。
struct CharacterGrowthManagementView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var pendingRemoval: CharacterGrowthArc?
    @State private var showsRemovalConfirmation = false
    @State private var showsClearConfirmation = false

    private var growth: CharacterGrowthSnapshot { viewModel.character.growth }

    var body: some View {
        Form {
            Section {
                Toggle("允许形成新的成长", systemImage: "leaf.fill", isOn: growthEnabledBinding)
            } header: {
                Text("未来互动")
            } footer: {
                Text("关闭后，新的聊天不会继续改变这位旅伴；已经形成的成长仍会保留并影响后续相处。")
            }

            Section {
                if growth.arcs.isEmpty {
                    ContentUnavailableView(
                        "还没有形成成长",
                        systemImage: "leaf",
                        description: Text("持续且有意义的互动，才会让变化从一个想法慢慢形成习惯。")
                    )
                } else {
                    ForEach(growth.arcs.sorted { $0.updatedAt > $1.updatedAt }) { arc in
                        growthRow(arc)
                    }
                }
            } header: {
                HStack {
                    Text("已形成的成长")
                    Spacer()
                    if growth.isPaused {
                        Label("已暂停", systemImage: "pause.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("每项变化都来自多次互动证据，不会覆盖角色的稳定人格。撤销后，该成长将不再影响 NPC 的后续回应。")
            }

            if !growth.arcs.isEmpty {
                Section {
                    Button("清空全部成长", role: .destructive) {
                        showsClearConfirmation = true
                    }
                } footer: {
                    Text("只清除关系中形成的成长；聊天记录、共同经历和基础人格都会保留。")
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.dsDanger)
                }
            }
        }
        .navigationTitle("成长与记忆")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isWorking)
        .overlay {
            if isWorking { ProgressView().controlSize(.large) }
        }
        .confirmationDialog(
            pendingRemoval.map { "撤销“\(growthTitle($0))”？" } ?? "撤销这项成长？",
            isPresented: $showsRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("撤销这项成长", role: .destructive) {
                guard let pendingRemoval else { return }
                removeArc(pendingRemoval)
            }
        } message: {
            Text("该成长将不再影响 NPC 的后续回应；稳定人格、聊天记录与共同经历不会改变。")
        }
        .confirmationDialog(
            "清空全部关系成长？",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空全部成长", role: .destructive) { clearGrowth() }
        } message: {
            Text("所有已形成的关系成长都会被撤销；稳定人格、聊天记录与共同经历不会改变。此操作无法撤销。")
        }
    }

    private var growthEnabledBinding: Binding<Bool> {
        Binding(
            get: { !growth.isPaused },
            set: { isEnabled in
                performUpdate {
                    try await viewModel.setCharacterGrowthPaused(!isEnabled)
                }
            }
        )
    }

    private func growthRow(_ arc: CharacterGrowthArc) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(growthTitle(arc))
                    .font(.headline)
                Spacer()
                Text(arc.stage.titleZh)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dsSkyDeep)
            }
            Text(arc.reasonZh)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: min(max(arc.progress, 0), 1))
                .tint(Color.dsSky)
            HStack {
                Label("\(arc.evidenceMessageIDs.count) 条互动证据", systemImage: "quote.bubble")
                Spacer()
                Text(arc.updatedAt.formatted(date: .abbreviated, time: .omitted))
                Button("撤销", role: .destructive) {
                    pendingRemoval = arc
                    showsRemovalConfirmation = true
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }

    private func growthTitle(_ arc: CharacterGrowthArc) -> String {
        switch arc.direction {
        case .increase: "更有\(arc.trait.titleZh)"
        case .decrease: "减少\(arc.trait.titleZh)"
        }
    }

    private func performUpdate(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await operation()
                Haptics.selection()
            } catch {
                errorMessage = "成长设置没有保存成功，请重试。"
            }
            isWorking = false
        }
    }

    private func removeArc(_ arc: CharacterGrowthArc) {
        performUpdate {
            try await viewModel.removeCharacterGrowthArc(id: arc.id)
        }
    }

    private func clearGrowth() {
        performUpdate {
            try await viewModel.clearCharacterGrowth()
        }
    }
}
