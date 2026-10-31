import CoreKit
import DesignSystem
import DomainKit
import PersistenceKit
import SpeechKit
import SwiftUI

public struct PlacementDependencies: Sendable {
    public let questionBankURL: URL
    public let economyStore: EconomyStore
    public let profileCommands: any ProfileCommandGateway
    public let speech: any SpeechService
    public let audioSession: AudioSessionCoordinator
    public let levelChangeSummary: @Sendable (DifficultyLevel) async throws -> String

    public init(
        questionBankURL: URL,
        economyStore: EconomyStore,
        profileCommands: any ProfileCommandGateway,
        speech: any SpeechService,
        audioSession: AudioSessionCoordinator,
        levelChangeSummary: @escaping @Sendable (DifficultyLevel) async throws -> String
    ) {
        self.questionBankURL = questionBankURL
        self.economyStore = economyStore
        self.profileCommands = profileCommands
        self.speech = speech
        self.audioSession = audioSession
        self.levelChangeSummary = levelChangeSummary
    }
}

/// 从基础开始的渐进测评；草稿、确认、回退与计分由同一会话管理。
public struct PlacementTestView: View {
    enum Phase: Equatable {
        case loading
        case introduction
        case levelSelection
        case question
        case result
        case failure
    }

    let startsWithLevelSelection: Bool
    let startsWithQuestions: Bool
    let usesNativeNavigation: Bool
    let deps: PlacementDependencies
    let onComplete: (UserProfileDTO) -> Void
    let onCancel: () -> Void
    @State var listeningPlayer: PlacementListeningAudioPlayer

    @State var hasPrepared = false
    @State var phase: Phase = .loading
    @State var questions: [PlacementQuestion] = []
    @State var session: PlacementSession?
    var engine: AdaptivePlacementEngine? { session?.engine }
    var currentQuestion: PlacementQuestion? { session?.current?.question }
    var optionOrder: [Int] { session?.current?.optionOrder ?? [] }
    var selectedOriginalIndex: Int? { session?.current?.selectedIndex }
    var listeningPlayCount: Int { session?.current?.listeningPlayCount ?? 0 }
    @State var listeningGeneration = UUID()
    @State var isListeningAudioLoading = false
    @State var isListeningAudioPlaying = false
    @State var result: PlacementResult?
    @State var currentLevel: DifficultyLevel = .junior3
    @State var selectedLevel: DifficultyLevel = .junior3
    @State var levelSelectionReturnPhase: Phase = .introduction
    @State var questionBankError: String?
    struct PendingLevelChange {
        let level: DifficultyLevel
        let result: PlacementResult?
        let summary: String
    }
    @State var pendingLevelChange: PendingLevelChange?
    @State var showLevelChangeConfirmation = false
    @State var isApplying = false
    @State var errorMessage: String?
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    public init(
        deps: PlacementDependencies,
        usesNativeNavigation: Bool = false,
        startsWithLevelSelection: Bool = false,
        startsWithQuestions: Bool = false,
        onComplete: @escaping (UserProfileDTO) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.startsWithLevelSelection = startsWithLevelSelection
        self.startsWithQuestions = startsWithQuestions
        self.usesNativeNavigation = usesNativeNavigation
        self.deps = deps
        self.onComplete = onComplete
        self.onCancel = onCancel
        _listeningPlayer = State(
            initialValue: PlacementListeningAudioPlayer(audioSession: deps.audioSession, speech: deps.speech)
        )
    }

    public var body: some View {
        ZStack {
            DSWorkbenchBackdrop(focus: .learning)

            Group {
                switch phase {
                case .loading:
                    loadingView
                case .introduction:
                    introductionView
                case .levelSelection:
                    DifficultyLevelSelectionPage(
                        selection: $selectedLevel,
                        currentLevel: currentLevel,
                        recommendedLevel: levelSelectionReturnPhase == .result && result?.hasSufficientEvidence == true
                            ? result?.difficultyLevel
                            : nil,
                        onDone: { applySelectedLevel(testResult: levelSelectionReturnPhase == .result ? result : nil) }
                    )
                    .disabled(isApplying)
                    .overlay(alignment: .top) {
                        if let errorMessage {
                            Text(errorMessage).font(.footnote).foregroundStyle(.red)
                                .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                case .question:
                    questionView
                case .result:
                    resultView
                case .failure:
                    failureView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .placementTopBar {
            if !usesNativeNavigation || phase != .introduction {
                header
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.top, 2)
                    .padding(.bottom, 5)
            }
        }
        // The photographic workbench stays light in both system appearances.
        .foregroundStyle(Color.dsPaperInk)
        .navigationTitle("英语水平校准")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(usesNativeNavigation && phase == .introduction ? .visible : .hidden, for: .navigationBar)
        .task { await prepareIfNeeded() }
        .alert("确认切换英语水平", isPresented: $showLevelChangeConfirmation) {
            Button("保持当前水平", role: .cancel) { pendingLevelChange = nil }
            Button("确认切换") {
                if let pendingLevelChange { saveSelectedLevel(level: pendingLevelChange.level, testResult: pendingLevelChange.result) }
                pendingLevelChange = nil
            }
        } message: { Text(pendingLevelChange?.summary ?? "") }
        .onDisappear {
            listeningGeneration = UUID()
            listeningPlayer.stop()
            isListeningAudioLoading = false; isListeningAudioPlaying = false
            Task { await deps.speech.stopSpeaking() }
        }
        .dsTabBarHidden()
        .interactiveDismissDisabled(
            phase == .question || phase == .levelSelection || isApplying
        )
    }

    private var header: some View {
        HStack {
            Button {
                if phase == .levelSelection {
                    closeLevelSelection()
                } else {
                    onCancel()
                }
            } label: {
                Image(systemName: phase == .levelSelection ? "chevron.left" : "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DSReadingPalette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .dsSceneGlass(
                radius: 22,
                tint: Color.dsBrandCream.opacity(0.08),
                interactive: true,
                legibility: .ambient
            )
            .disabled(isApplying)
            .accessibilityLabel(phase == .levelSelection ? "返回水平校准" : "退出水平校准")

            Spacer()
            VStack(spacing: 1) {
                Text(phase == .levelSelection ? "选择英语水平" : "英语水平校准")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.dsPaperInk)
                if phase == .question, let engine {
                    Text("已确认 \(engine.responses.count) 题")
                        .font(.caption2)
                        .foregroundStyle(Color.dsPaperInkSecondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.985, green: 0.970, blue: 0.925).opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    var loadingView: some View {
        VStack(spacing: DSSpacing.sm) {
            ProgressView()
                .tint(.dsSky)
            Text("正在准备合适的题目…")
                .font(.subheadline)
                .foregroundStyle(Color.dsPaperInkSecondary)
        }
        .padding(DSSpacing.lg)
        .placementPaperPanel()
    }

    private var introductionView: some View {
        ScrollView {
            VStack(spacing: DSSpacing.md) {
                VStack(spacing: 6) {
                    BrandMascotView(
                        pose: .guide,
                        size: 116,
                        showsShadow: true
                    )

                    Text("选择或测一测，聊得更合拍")
                        .font(.system(.title2, design: .default, weight: .bold))
                        .foregroundStyle(Color.dsPaperInk)
                        .multilineTextAlignment(.center)
                    Text("从基础开始测一测，找到适合现在的学习起点。")
                        .font(.subheadline)
                        .foregroundStyle(Color.dsPaperInkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .placementPaperPanel()

                DSWorkbenchPaperSheet(padding: 0) {
                    VStack(spacing: 0) {
                        levelSelectionButton(
                            title: "当前英语水平",
                            detail: "可随时修改",
                            recommendedLevel: nil
                        )

                        Divider()
                            .overlay(Color.dsPaperInk.opacity(0.12))

                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            HStack(spacing: DSSpacing.md) {
                                DSObsidianMedallion(systemImage: "safari", size: 58)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("渐进式水平测评")
                                        .font(.system(.title3, design: .default, weight: .bold))
                                        .foregroundStyle(Color.dsPaperInk)
                                    Text("完成后给出适合你的对话难度建议")
                                        .font(.caption)
                                        .foregroundStyle(Color.dsPaperInkSecondary)
                                }
                            }

                            informationRow(
                                icon: "slider.horizontal.3",
                                title: "从易到难，最多 20 题",
                                detail: "累计答错 3 次即结束，按实际作答给出建议"
                            )
                            informationRow(
                                icon: "headphones",
                                title: "以词汇、语法和阅读为主",
                                detail: "听力最多 2 题，不放在开头，可跳过"
                            )
                            informationRow(
                                icon: "lock.shield",
                                title: "不公开排名",
                                detail: "结果只用于调整角色对话难度"
                            )

                            if let questionBankError {
                                Label(questionBankError, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(Color.dsSunset)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Button("开始水平测试") { start() }
                                .buttonStyle(.dsWorkbenchAction)
                                .disabled(engine == nil || isApplying)

                            Label(
                                "选好后点击确认；可返回上一题或跳过，跳过不计为答错。",
                                systemImage: "lightbulb"
                            )
                            .font(.caption)
                            .foregroundStyle(Color.dsPaperInkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(DSSpacing.md)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.dsDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 560)
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity)
        }
        .placementScrollEdgeBlend()
    }

    @ViewBuilder
    private var questionView: some View {
        if let question = currentQuestion, let engine {
            VStack(
                spacing: DSPlatformVisualPolicy.requiresIOS18RenderingCompensation
                    ? DSSpacing.sm
                    : 0
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(
                        value: engine.measurementProgress
                    )
                    .tint(.dsSky)
                    HStack {
                        Label(
                            "\(question.skill.displayName) · \(question.format.displayName)",
                            systemImage: skillIcon(question.skill)
                        )
                        Spacer()
                        Text("第 \((session?.cursor ?? 0) + 1) 题 / 20")
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dsPaperInkSecondary)
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.sm)
                .placementPaperPanel(padding: 0, weight: .chrome)
                .padding(.horizontal, DSSpacing.lg)

                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.lg) {
                        Text(question.prompt)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("placement.prompt")
                            .font(.system(.title3, design: .default, weight: .bold))
                            .foregroundStyle(Color.dsPaperInk)
                            .fixedSize(horizontal: false, vertical: true)

                        if question.skill == .listening {
                            listeningCard(question)
                        } else if let context = question.context {
                            Text(context)
                                .font(.body)
                                .lineSpacing(5)
                                .foregroundStyle(Color.dsPaperInkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DSSpacing.md)
                                .background(
                                    Color.dsPaperInk.opacity(0.045),
                                    in: RoundedRectangle(cornerRadius: DSRadius.inline)
                                )
                        }

                        VStack(spacing: DSSpacing.sm) {
                            ForEach(optionOrder, id: \.self) { originalIndex in
                                optionButton(
                                    question.options[originalIndex],
                                    originalIndex: originalIndex
                                )
                            }
                        }

                        Text("选好后确认再进入下一题，确认前可以修改。")
                            .font(.caption)
                            .foregroundStyle(Color.dsPaperInkSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(maxWidth: 560)
                    .padding(DSSpacing.lg)
                    .placementPaperPanel(padding: 0)
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.bottom, DSSpacing.xl)
                    .frame(maxWidth: .infinity)
                }
                .id(question.id)
                .placementScrollEdgeBlend()
            }
            .placementBottomBar {
                VStack(spacing: 8) {
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(Color.dsDanger)
                    }
                    HStack(spacing: 12) {
                        Button { previousQuestion() } label: {
                            Text("上一题").frame(minWidth: 64, minHeight: 48).contentShape(Rectangle())
                        }
                            .disabled(session?.canGoBack != true)
                            .opacity(session?.canGoBack == true ? 1 : 0.4)
                            .accessibilityIdentifier("placement.previous")
                        Spacer()
                        Button { advanceQuestion(skipping: true) } label: {
                            Text("跳过").frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
                        }
                            .accessibilityIdentifier("placement.skip")
                        Button("确认答案") { advanceQuestion(skipping: false) }
                            .buttonStyle(.dsAction(.primary, fullWidth: false))
                            .disabled(session?.canConfirm != true)
                            .opacity(session?.canConfirm == true ? 1 : 0.45)
                            .accessibilityIdentifier("placement.confirm")
                    }
                    .frame(minHeight: 48)
                }
                .padding(.horizontal, DSSpacing.lg).padding(.vertical, DSSpacing.sm)
                .background(.regularMaterial)
            }
        } else {
            loadingView
        }
    }

    private func listeningCard(_ question: PlacementQuestion) -> some View {
        let canPlay = PlacementListeningPolicy.canPlay(currentCount: listeningPlayCount)
            && !isListeningAudioLoading
        let remaining = PlacementListeningPolicy.remainingPlayCount(after: listeningPlayCount)
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Button {
                playListeningQuestion(question)
            } label: {
                HStack(spacing: DSSpacing.sm) {
                    Image(
                        systemName: isListeningAudioLoading
                            ? "speaker.wave.2.circle.fill"
                            : !canPlay
                            ? "speaker.slash.circle.fill"
                            : listeningPlayCount == 0
                                ? "play.circle.fill"
                                : "speaker.wave.2.circle.fill"
                    )
                    .font(.title2)
                    if isListeningAudioLoading {
                        ProgressView()
                            .tint(Color.dsSkyDeep)
                    }
                    Text(
                        isListeningAudioLoading
                            ? (isListeningAudioPlaying ? "正在播放" : "正在准备声音…")
                            : !canPlay
                            ? "已达到播放上限"
                            : listeningPlayCount == 0 ? "第一遍 · 美音" : "第二遍 · 英音"
                    )
                        .font(.headline)
                    Spacer()
                    Text("\(listeningPlayCount) / \(PlacementListeningPolicy.maximumPlayCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.dsPaperInkSecondary)
                }
                .foregroundStyle(Color.dsSkyDeep)
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .disabled(!canPlay)
            .accessibilityLabel(canPlay ? "播放听力音频" : "听力音频播放次数已用完")
            .accessibilityValue("已播放 \(listeningPlayCount) 次，最多 2 次")
            .accessibilityHint(canPlay ? "播放后即可选择答案，还可播放 \(remaining) 次" : "请根据已听内容作答")

            Text(
                listeningPlayCount == 0
                    ? "先听音频，再根据内容作答；每题最多播放 2 次，先美音后英音。"
                    : canPlay
                        ? "还可播放 \(remaining) 次；音频文本不会显示。"
                        : "本题播放次数已用完，请根据已听内容作答。"
            )
            .font(.caption)
            .foregroundStyle(Color.dsPaperInkSecondary)
        }
    }
}
