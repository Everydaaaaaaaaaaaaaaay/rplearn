import BackendKit
import CoreKit
import DomainKit
import DesignSystem
import PersistenceKit
import SwiftUI

public struct CharacterLearningView: View {
    @State private var model: CharacterLearningModel
    private let character: CharacterDTO
    private let isVisible: Bool
    private let audioSession: AudioSessionCoordinator
    private let beforePlayback: @Sendable () async -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var showJourney = false
    @State private var onlyUnfinished = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    public init(character: CharacterDTO, service: any LearningServing, isVisible: Bool = true,
                audioSession: AudioSessionCoordinator = AudioSessionCoordinator(),
                beforePlayback: @escaping @Sendable () async -> Void = {},
                cycleChanged: @escaping @Sendable () async -> Void = {}) {
        self.character = character; self.isVisible = isVisible
        self.audioSession = audioSession; self.beforePlayback = beforePlayback
        _model = State(initialValue: CharacterLearningModel(characterID: character.id, service: service,
                                                           cycleChanged: cycleChanged))
    }
    private var theme: LearningTheme { LearningTheme(role: model.state?.roleKey ?? character.card.name.components(separatedBy: " ").first?.lowercased() ?? "") }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let error = model.error {
                    LearningPageError(message: error) { Task { await model.load() } }
                }
                if let state = model.state {
                    VStack(spacing: 0) {
                        progressCard(state)
                        if let journey = model.journey {
                            Divider().padding(.horizontal, 18)
                            globalCard(journey)
                        }
                    }
                    .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 22))
                    historySection
                } else if model.isBusy {
                    ProgressView("正在载入…")
                        .font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 28)
            .frame(maxWidth: 600).frame(maxWidth: .infinity)

        }
        .background(Color.dsBackground)
        .tint(theme.tint)
        .refreshable { await model.load() }
        .task(id: isVisible) { if isVisible { await model.load() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isVisible { Task { await model.load() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .roleplayConversationDidChange)) { notification in
            if isVisible && notification.object as? UUID == character.id { Task { await model.load() } }
        }
        .fullScreenCover(item: $model.presentedAttempt, onDismiss: { Task { await model.challengeClosed() } }) { attempt in
            LearningChallengeView(attempt: attempt, character: character, service: model.service, audioSession: audioSession,
                                  beforePlayback: beforePlayback, afterFinish: { await model.refreshCycle() })
        }
        .sheet(isPresented: $showJourney) {
            NavigationStack {
                LearningProgressOverview(service: model.service)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showJourney = false } } }
            }
        }
        .accessibilityIdentifier("learning.character")
    }
    private func progressCard(_ state: BackendLearningCharacter) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    challengeTitle
                    Text(challengeStatus(state)).font(.caption.weight(.medium)).foregroundStyle(theme.tint)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    challengeTitle
                    Spacer(minLength: 8)
                    Text(challengeStatus(state)).font(.caption.weight(.medium)).foregroundStyle(theme.tint)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        HStack(alignment: .firstTextBaseline) {
                            characterCount(state)
                            Spacer(minLength: 12)
                            remainingCount(state)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        characterCount(state)
                        remainingCount(state)
                    }
                }
                LearningMeter(value: state.characters, total: state.threshold, tint: theme.tint)
                    .accessibilityLabel("挑战进度")
                    .accessibilityValue("\(state.characters) / \(state.threshold) 字符")
            }
            if state.activeAttemptId != nil || state.characters >= state.threshold {
                Button {
                    Task { await model.open() }
                } label: {
                    HStack(spacing: 8) {
                        if model.isBusy { ProgressView().tint(Color.dsSurface) }
                        Text(state.activeAttemptId != nil ? "继续挑战" : model.isPreparing ? "刷新状态" : "开始挑战")
                        Spacer()
                        Image(systemName: model.isPreparing ? "arrow.clockwise" : "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).frame(minHeight: 46)
                    .foregroundStyle(Color.dsSurface)
                    .background(theme.tint, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(LearningPressStyle()).disabled(model.isBusy)
                .accessibilityIdentifier("learning.start")
            }
        }.padding(18)
    }
    private var challengeTitle: some View {
        HStack(spacing: 8) {
            Image(systemName: theme.symbol).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.tint).accessibilityHidden(true)
            Text("单元挑战").font(.headline)
        }
    }
    private func characterCount(_ state: BackendLearningCharacter) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.characters.formatted()).font(.system(.title, design: .rounded, weight: .semibold))
                    Text("目标 \(state.threshold.formatted()) 字符").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(state.characters.formatted()).font(.system(.title, design: .rounded, weight: .semibold))
                    Text("/ \(state.threshold.formatted()) 字符").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.monospacedDigit().accessibilityElement(children: .combine)
    }
    private func remainingCount(_ state: BackendLearningCharacter) -> some View {
        Group {
            if state.characters < state.threshold {
                Text("还差 \(max(0, state.threshold - state.characters))")
            } else {
                Text("已满")
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
    private func challengeStatus(_ state: BackendLearningCharacter) -> String {
        if state.activeAttemptId != nil { return "进行中" }
        if model.isPreparing { return "单元准备中" }
        return state.characters >= state.threshold ? "可开启" : "聊天积累中"
    }
    private func globalCard(_ journey: LearningJourney) -> some View {
        Button { showJourney = true } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(learningLevelName(journey.currentLevel)).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 12)
                            nextStar(journey.current)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(learningLevelName(journey.currentLevel)).font(.subheadline.weight(.semibold))
                            nextStar(journey.current)
                        }
                    }
                    LearningMilestones(earned: journey.current?.stars ?? 0, tint: theme.tint)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
            }.padding(18).contentShape(Rectangle())
        }
        .buttonStyle(LearningPressStyle()).foregroundStyle(.primary)
        .accessibilityHint("查看英语旅程")
        .accessibilityIdentifier("learning.journey")
    }
    private func nextStar(_ current: LearningLevelProgress?) -> some View {
        Text((current?.stars ?? 0) >= 9 ? "9 星已达成" : "下一星  \(current?.currentStarPoints ?? 0)/\(current?.pointsPerStar ?? 60) 点")
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }
    private var visibleHistory: [LearningHistory.Item] {
        onlyUnfinished ? model.history.filter { $0.firstCompletedAt != nil && $0.correctCount < $0.questionCount } : model.history
    }
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("挑战记录").font(.headline)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
            }.padding(.horizontal, 2)
            if !model.history.isEmpty {
                Picker("挑战记录", selection: $onlyUnfinished) {
                    Text("全部").tag(false)
                    Text("待补答").tag(true)
                }
                .pickerStyle(.segmented).accessibilityIdentifier("learning.history.filter")
            }
            if visibleHistory.isEmpty {
                Label(onlyUnfinished ? "暂无待补答记录" : "暂无挑战记录", systemImage: "tray")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20).padding(.horizontal, 2)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visibleHistory) { item in
                        if item.id != visibleHistory.first?.id { Divider().padding(.leading, 16) }
                        historyRow(item)
                    }
                }
                .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 18))
            }
            if model.nextCursor != nil {
                Button("载入更多") { Task { await model.loadMore() } }
                    .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(model.isBusy)
            }
        }
    }
    private func historyRow(_ item: LearningHistory.Item) -> some View {
        Button { Task { await model.open(item.id) } } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title).font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 3) { historyMetadata(item) }
                    } else {
                        HStack(spacing: 10) { historyMetadata(item) }
                    }
                    if dynamicTypeSize.isAccessibilitySize { historyAction(item) }
                }
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize { historyAction(item) }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(LearningPressStyle()).foregroundStyle(.primary).disabled(model.isBusy)
        .accessibilityIdentifier("learning.history.\(item.id.uuidString)")
    }
    @ViewBuilder private func historyMetadata(_ item: LearningHistory.Item) -> some View {
        Text(learningLevelName(item.level)).font(.caption).foregroundStyle(.secondary)
        Text("答对 \(item.correctCount)/\(item.questionCount)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }
    private func historyAction(_ item: LearningHistory.Item) -> some View {
        let complete = item.firstCompletedAt != nil && item.correctCount == item.questionCount
        return Text(item.firstCompletedAt == nil ? "继续" : complete ? "已完成" : "补答 \(max(0, item.questionCount - item.correctCount)) 题")
            .font(.caption.weight(.medium))
            .foregroundStyle(complete ? Color.secondary : theme.tint)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(complete ? Color.dsSurfaceMuted : theme.tint.opacity(0.08), in: Capsule())
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
    }

}

/// 角色页的全局摘要；完整英语旅程的主线和改档入口由 App 装配。
public struct LearningProgressOverview: View {
    private let service: any LearningServing
    @State private var journey: LearningJourney?
    @State private var error: String?
    public init(service: any LearningServing) { self.service = service }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error { LearningPageError(message: error) { Task { await load() } } }
                if let journey, let current = journey.current {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(learningLevelName(journey.currentLevel)).font(.title2.weight(.semibold))
                            Spacer()
                            Text("\(current.stars)/9 星").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }
                        LearningMilestones(earned: current.stars, tint: .dsSkyDeep)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(current.stars >= 9 ? "本级累计" : "下一颗星").font(.subheadline)
                                Spacer()
                                Text(current.stars >= 9 ? "\(current.points) 点" : "\(current.currentStarPoints)/\(current.pointsPerStar) 点")
                                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                            }
                            LearningMeter(value: current.stars >= 9 ? current.targetPoints : current.currentStarPoints,
                                          total: current.stars >= 9 ? current.targetPoints : current.pointsPerStar, tint: .dsSkyDeep)
                        }
                    }.padding(20).background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 20))
                } else if error == nil {
                    ProgressView("正在载入…").frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            }.padding(16).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .background(Color.dsBackground).navigationTitle("英语旅程").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        do { journey = try await service.learningJourney(); error = nil }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

private struct LearningMeter: View {
    let value: Int
    let total: Int
    let tint: Color
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(tint.opacity(0.10))
                .overlay(alignment: .leading) {
                    Capsule().fill(tint)
                        .frame(width: geometry.size.width * min(1, max(0, Double(value) / Double(max(1, total)))))
                }
        }.frame(height: 7)
    }
}

private struct LearningMilestones: View {
    let earned: Int
    let tint: Color
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<9) { index in
                Image(systemName: index < earned ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(index < earned ? tint : Color.secondary.opacity(0.6))
                if index < 8 {
                    Rectangle().fill(Color.secondary.opacity(0.12)).frame(height: 1).padding(.horizontal, 5)
                }
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("已点亮 \(earned) 颗星，共 9 颗")
    }
}

private struct LearningPageError: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(message).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: retry) {
                Image(systemName: "arrow.clockwise").font(.body.weight(.medium)).frame(width: 44, height: 44)
            }.accessibilityLabel("重新载入")
        }
        .padding(.leading, 16).padding(.trailing, 4).padding(.vertical, 8)
        .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 16))
    }
}
