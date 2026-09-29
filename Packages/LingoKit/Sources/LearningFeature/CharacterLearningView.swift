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
            VStack(alignment: .leading, spacing: 22) {
                header
                if let error = model.error { LearningErrorBanner(message: error) { Task { await model.load() } } }
                if let state = model.state {
                    progressCard(state)
                    if let journey = model.journey { globalCard(journey) }
                    historySection
                } else if model.isBusy {
                    ProgressView("正在打开活动册…").frame(maxWidth: .infinity).padding(60)
                } else {
                    ContentUnavailableView("暂时无法打开学习页", systemImage: "book.closed", description: Text("请重新载入。聊天记录仍会保存在设备中。"))
                }
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
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
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(theme.caption, systemImage: theme.symbol).font(.caption.weight(.semibold)).foregroundStyle(theme.tint)
                Text("一起学到的，\n慢慢变成你的。").font(.system(.largeTitle, design: .serif).weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(character.displayName).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            AvatarBadge(name: character.displayName, size: 64, imageName: character.card.avatarAssetName,
                        remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)), usesPendingPlaceholder: true)
                .rotationEffect(.degrees(4)).accessibilityHidden(true)
        }.padding(.vertical, 12)
    }
    private func progressCard(_ state: BackendLearningCharacter) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(state.activeAttemptId != nil ? "一段挑战，等你继续" : "下一段单元挑战").font(.headline)
                Spacer()
                Image(systemName: theme.symbol).foregroundStyle(theme.tint).accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(state.characters.formatted()).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("/ \(state.threshold) 字符").font(.subheadline).foregroundStyle(.secondary)
            }.accessibilityElement(children: .combine)
            ProgressView(value: Double(state.characters), total: Double(max(1, state.threshold)))
                .tint(theme.tint).scaleEffect(y: 2).padding(.vertical, 4)
            Text(state.activeAttemptId != nil ? "完成本轮后，这里的进度会重新积累。" : state.characters >= state.threshold ? "聊天积累已满，去一段新的情景里试试吧。" : "你和旅伴发出的正文都会积累进度，还差 \(max(0, state.threshold - state.characters)) 字符。")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.isPreparing {
                Label("正在准备新的单元。进度会保留，稍后可再来查看。", systemImage: "clock")
                    .font(.subheadline).foregroundStyle(theme.tint)
            }
            if state.activeAttemptId != nil || state.characters >= state.threshold {
                LearningPrimaryButton(title: state.activeAttemptId != nil ? "继续挑战" : model.isPreparing ? "查看准备进度" : "开始单元挑战", tint: theme.tint, busy: model.isBusy) {
                    Task { await model.open() }
                }.accessibilityIdentifier("learning.start")
            } else {
                Label("回到聊天，继续积累", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.medium)).foregroundStyle(theme.tint)
            }
        }.modifier(LearningPaper())
    }
    private func globalCard(_ journey: LearningJourney) -> some View {
        Button { showJourney = true } label: {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("英语旅程 · 全局水平").font(.caption).foregroundStyle(.secondary)
                        Text(learningLevelName(journey.currentLevel)).font(.headline)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(theme.tint)
                }
                LearningStars(earned: journey.current?.stars ?? 0, tint: theme.tint)
                Text("每位旅伴的挑战，共同积累你的英语水平。")
                    .font(.caption).foregroundStyle(.secondary)
            }.modifier(LearningPaper())
        }.buttonStyle(LearningPressStyle()).foregroundStyle(.primary)
    }
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("单元足迹").font(.title2.bold()); Spacer(); Text("\(model.history.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            if model.history.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "book.pages").font(.title).foregroundStyle(theme.tint)
                    Text("第一段挑战，从聊天开始。 ").font(.headline)
                    Text("达到 1000 字符后开启。完成的单元会留在这里，答错的题可以回来补答。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.modifier(LearningPaper())
            }
            ForEach(model.history) { item in
                Button { Task { await model.open(item.id) } } label: {
                    HStack(spacing: 15) {
                        Image(systemName: item.correctCount == item.questionCount ? "checkmark.seal.fill" : "bookmark")
                            .font(.title2).foregroundStyle(theme.tint).frame(width: 36)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(item.title).font(.headline)
                            Text(learningLevelName(item.level)).font(.caption).foregroundStyle(.secondary)
                            Text(item.firstCompletedAt == nil ? "首轮进行中 · 已答对 \(item.correctCount)/\(item.questionCount)" : item.correctCount == item.questionCount ? "全部掌握 · \(item.correctCount) 点已获得" : "已答对 \(item.correctCount)/\(item.questionCount) · 还可获得 \(item.questionCount - item.correctCount) 点")
                                .font(.caption).foregroundStyle(theme.tint)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.modifier(LearningPaper())
                }.buttonStyle(LearningPressStyle()).foregroundStyle(.primary).disabled(model.isBusy)
            }
            if model.nextCursor != nil { Button("更多记录") { Task { await model.loadMore() } }.frame(maxWidth: .infinity).padding().disabled(model.isBusy) }
        }
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
            VStack(alignment: .leading, spacing: 24) {
                if let journey, let current = journey.current {
                    Text(learningLevelName(journey.currentLevel)).font(.largeTitle.bold())
                    Text("不同角色的挑战，汇入同一段成长。").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 22) {
                        LearningStars(earned: current.stars, tint: .dsSkyDeep)
                        ProgressView(value: Double(current.currentStarPoints), total: Double(current.pointsPerStar)).tint(.dsSkyDeep)
                        Text(current.stars >= 9 ? "九颗星已点亮" : "下一颗星：\(current.currentStarPoints) / \(current.pointsPerStar) 点").font(.headline)
                        Text("每道首次答对的题获得 1 点。补答只增加之前没有获得的点数；不同年级分别保留进度。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.modifier(LearningPaper())
                } else if let error { LearningErrorBanner(message: error) { Task { await load() } } }
                else { ProgressView("正在载入旅程…") }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(Color.dsBackground).navigationTitle("英语旅程").task { await load() }
    }
    private func load() async { do { journey = try await service.learningJourney(); error = nil } catch { self.error = error.localizedDescription } }
}
