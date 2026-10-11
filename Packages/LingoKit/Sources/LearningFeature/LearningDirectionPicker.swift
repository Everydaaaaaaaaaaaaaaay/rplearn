import BackendKit
import DesignSystem
import SwiftUI

struct LearningDirectionPicker: View {
    @Bindable var model: CharacterLearningModel
    @Environment(\.dismiss) private var dismiss
    @State private var candidate: LearningDirectionOption?
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let error = model.directionError {
                        LearningPageError(message: error) {
                            Task {
                                if let pending = model.pendingDirection { await model.selectDirection(pending) }
                                else { await model.load() }
                            }
                        }.padding(.bottom, 16)
                    }
                    if let state = model.directions {
                        ForEach(state.directions) { option in
                            Button {
                                candidate = option; confirming = true
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(option.title).font(.body.weight(.medium))
                                        if option.status != "available" {
                                            Text("准备中").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 12)
                                    if option.id == state.selectedDirection {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                    }
                                }
                                .padding(.vertical, 16).frame(minHeight: 64)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).foregroundStyle(.primary)
                            .disabled(model.isBusy || model.isChangingDirection || model.pendingDirection != nil || option.id == state.selectedDirection)
                            .accessibilityValue(option.id == state.selectedDirection ? "已选择" : option.status == "available" ? "可用" : "准备中")
                            .accessibilityIdentifier("learning.direction.\(option.id)")
                            Divider()
                        }
                    } else if model.isBusy || model.isChangingDirection {
                        ProgressView().frame(maxWidth: .infinity).padding(32)
                    }
                }.padding(.horizontal, 20).padding(.top, 8)
            }
            .background(Color.dsBackground)
            .navigationTitle("练习方向").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("关闭练习方向")
                }
            }
            .confirmationDialog("切换到\(candidate?.title ?? "此方向")？", isPresented: $confirming,
                                titleVisibility: .visible, presenting: candidate) { option in
                Button("切换") {
                    Task {
                        await model.selectDirection(option.id)
                        if model.directionError == nil { dismiss() }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: { option in
                Text(option.status == "available"
                     ? "之后的新挑战使用这个方向。当前挑战和补答保留。"
                     : "题目准备中，暂不能开启新挑战。当前挑战和补答保留。")
            }
        }
        .interactiveDismissDisabled(model.isChangingDirection)
        .accessibilityIdentifier("learning.directions")
    }
}
