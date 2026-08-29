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

    public init(
        questionBankURL: URL,
        economyStore: EconomyStore,
        profileCommands: any ProfileCommandGateway,
        speech: any SpeechService
    ) {
        self.questionBankURL = questionBankURL
        self.economyStore = economyStore
        self.profileCommands = profileCommands
        self.speech = speech
    }
}

/// 依据答案动态控制在 14–20 题的自适应校准。
/// 测评过程中不显示对错、不允许回退，避免后续答案被提示影响。
public struct PlacementTestView: View {
    private enum Phase: Equatable {
        case loading
        case introduction
        case levelSelection
        case question
        case result
        case failure
    }

    private let deps: PlacementDependencies
    private let onComplete: (UserProfileDTO) -> Void
    private let onCancel: () -> Void

    @State private var phase: Phase = .loading
    @State private var questions: [PlacementQuestion] = []
    @State private var engine: AdaptivePlacementEngine?
    @State private var currentQuestion: PlacementQuestion?
    @State private var optionOrder: [Int] = []
    @State private var selectedOriginalIndex: Int?
    @State private var listeningPlayCount = 0
    @State private var result: PlacementResult?
    @State private var currentLevel: DifficultyLevel = .junior3
    @State private var selectedLevel: DifficultyLevel = .junior3
    @State private var levelSelectionReturnPhase: Phase = .introduction
    @State private var questionBankError: String?
    @State private var isApplying = false
    @State private var errorMessage: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        deps: PlacementDependencies,
        onComplete: @escaping (UserProfileDTO) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.deps = deps
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            PlacementCanvasBackground()

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
                        recommendedLevel: levelSelectionReturnPhase == .result
                            ? result?.difficultyLevel
                            : nil,
                        onDone: closeLevelSelection
                    )
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
        .placementTopBar { header }
        .task { await prepareIfNeeded() }
        .onDisappear {
            Task { await deps.speech.stopSpeaking() }
        }
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
                    .frame(width: 36, height: 36)
                    .dsMaterial(.thinMaterial, in: Circle())
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.55), lineWidth: 0.7)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isApplying)
            .accessibilityLabel(phase == .levelSelection ? "返回水平校准" : "退出水平校准")

            Spacer()
            VStack(spacing: 1) {
                Text(phase == .levelSelection ? "选择英语水平" : "英语水平校准")
                    .font(.subheadline.weight(.semibold))
                if phase == .question, let engine {
                    Text("已答 \(engine.responses.count) 题")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, DSSpacing.xs)
        .padding(.bottom, DSSpacing.sm)
    }

    private var loadingView: some View {
        VStack(spacing: DSSpacing.sm) {
            ProgressView()
                .tint(.dsSky)
            Text("正在准备合适的题目…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var introductionView: some View {
        ScrollView {
            VStack(spacing: DSSpacing.xl) {
                HStack(alignment: .top, spacing: DSSpacing.md) {
                    BrandMascotView(pose: .guide, size: 54, showsShadow: false)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("选择或测一测，聊得更合拍")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("直接选择当前水平，或通过短测获得建议。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                levelSelectionButton(
                    title: "直接选择英语水平",
                    detail: "无需答题，也可以随时重新修改。",
                    recommendedLevel: nil
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.dsDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    applySelectedLevel(testResult: nil)
                } label: {
                    if isApplying {
                        ProgressView().tint(.white)
                    } else {
                        Text("应用 \(selectedLevel.displayName)")
                    }
                }
                .buttonStyle(.dsActionPrimary)
                .disabled(isApplying)

                Label("想更准确？通过短测获取建议", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dsSkyDeep)

                VStack(spacing: 3) {
                    informationRow(
                        icon: "slider.horizontal.3",
                        title: "自适应题量",
                        detail: "答满 14 题后判断稳定度，最多 20 题，约 4–6 分钟"
                    )
                    informationRow(
                        icon: "headphones",
                        title: "四类能力，多种题型",
                        detail: "从 96 道题中动态抽取词汇、语法、阅读与听力题"
                    )
                    informationRow(
                        icon: "lock.shield",
                        title: "没有公开排名",
                        detail: "结果只用于调整角色对话难度"
                    )
                }
                .placementGlassPanel(padding: 0)

                if let questionBankError {
                    Label(questionBankError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.dsSunset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Label("凭第一感觉作答即可", systemImage: "lightbulb")
                        .font(.subheadline.weight(.semibold))
                    Text("测评中不会立即显示对错，也不能返回上一题。它是学习难度校准，不是官方证书考试。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("开始水平测试") {
                    start()
                }
                .buttonStyle(.dsAction(.tinted(.dsSkyDeep)))
                .disabled(engine == nil || isApplying)
            }
            .frame(maxWidth: 560)
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity)
        }
        .placementScrollEdgeBlend()
    }

    @ViewBuilder
    private var questionView: some View {
        if let question = currentQuestion, let engine {
            VStack(spacing: 0) {
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
                        Text("第 \(engine.responses.count + 1) 题")
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.md)

                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.lg) {
                        Text(question.prompt)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)

                        if question.skill == .listening {
                            listeningCard(question)
                        } else if let context = question.context {
                            Text(context)
                                .font(.body)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .placementGlassPanel()
                        }

                        VStack(spacing: DSSpacing.sm) {
                            ForEach(optionOrder, id: \.self) { originalIndex in
                                optionButton(
                                    question.options[originalIndex],
                                    originalIndex: originalIndex
                                )
                            }
                        }

                        Text("选择后会自动进入下一题，不显示即时对错。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(maxWidth: 560)
                    .padding(DSSpacing.lg)
                    .padding(.bottom, DSSpacing.xl)
                    .frame(maxWidth: .infinity)
                }
                .placementScrollEdgeBlend()
            }
        } else {
            loadingView
        }
    }

    private func listeningCard(_ question: PlacementQuestion) -> some View {
        let canPlay = PlacementListeningPolicy.canPlay(currentCount: listeningPlayCount)
        let remaining = PlacementListeningPolicy.remainingPlayCount(after: listeningPlayCount)
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Button {
                playListeningQuestion(question)
            } label: {
                HStack(spacing: DSSpacing.sm) {
                    Image(
                        systemName: !canPlay
                            ? "speaker.slash.circle.fill"
                            : listeningPlayCount == 0
                                ? "play.circle.fill"
                                : "speaker.wave.2.circle.fill"
                    )
                    .font(.title2)
                    Text(
                        !canPlay
                            ? "已达到播放上限"
                            : listeningPlayCount == 0 ? "播放音频" : "再听一次"
                    )
                        .font(.headline)
                    Spacer()
                    Text("\(listeningPlayCount) / \(PlacementListeningPolicy.maximumPlayCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.dsSkyDeep)
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .disabled(!canPlay)
            .accessibilityLabel(canPlay ? "播放听力音频" : "听力音频播放次数已用完")
            .accessibilityValue("已播放 \(listeningPlayCount) 次，最多 3 次")
            .accessibilityHint(canPlay ? "播放后即可选择答案，还可播放 \(remaining) 次" : "请根据已听内容作答")

            Text(
                listeningPlayCount == 0
                    ? "先听音频，再根据内容作答；每题最多播放 3 次。"
                    : canPlay
                        ? "还可播放 \(remaining) 次；音频文本不会显示。"
                        : "本题播放次数已用完，请根据已听内容作答。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .placementGlassPanel()
    }

    @ViewBuilder
    private var resultView: some View {
        if let result {
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    BrandMascotView(pose: .celebrate, size: 62, showsShadow: false)

                    VStack(spacing: 5) {
                        Text("校准完成")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.dsSkyDeep)
                        Text(result.difficultyLevel.displayName)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("完成 \(result.answeredCount) 道 · 测试建议水平")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: DSSpacing.md) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("综合校准")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(result.score) / 100")
                                    .font(.title2.bold().monospacedDigit())
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("90% 估计区间")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(result.scoreRange.lowerBound)–\(result.scoreRange.upperBound)")
                                    .font(.headline.monospacedDigit())
                            }
                        }

                        Divider()

                        HStack {
                            Label("判断稳定度", systemImage: "checkmark.seal")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(
                                "\(result.confidenceLabel) · "
                                    + "\(Int((result.levelConfidence * 100).rounded()))%"
                            )
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.dsSkyDeep)
                        }

                        HStack {
                            Label("CSE 参考", systemImage: "flag")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(result.difficultyLevel.cseReference) · 非认证")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Label("CEFR 辅助参考", systemImage: "globe.europe.africa")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(result.referenceLevel.rawValue) · 非认证")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        ForEach(result.skillResults) { skillResult in
                            skillResultRow(skillResult)
                        }
                    }
                    .placementGlassPanel(padding: DSSpacing.lg)

                    levelSelectionButton(
                        title: "最终应用水平",
                        detail: selectedLevel == result.difficultyLevel
                            ? "当前采用测试建议；你也可以自由选择其他水平。"
                            : "你选择了不同于测试建议的水平。",
                        recommendedLevel: result.difficultyLevel
                    )

                    Text(
                        "年级结果表示人教版一年级起点教材的学习进度估计；四六级结果表示相近学习难度。"
                            + "这是用于调整学习内容的短测，不代表通过任何官方考试。"
                            + "测试结果只是建议，最终应用哪个水平由你决定，也可以稍后再次修改。"
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Color.dsDanger)
                    }

                    Button {
                        applySelectedLevel(testResult: result)
                    } label: {
                        if isApplying {
                            ProgressView().tint(.white)
                        } else {
                            Text("应用 \(selectedLevel.displayName)")
                        }
                    }
                    .buttonStyle(.dsActionPrimary)
                    .disabled(isApplying)
                }
                .frame(maxWidth: 560)
                .padding(DSSpacing.lg)
                .frame(maxWidth: .infinity)
            }
            .placementScrollEdgeBlend()
        } else {
            loadingView
        }
    }

    private var failureView: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.dsSunset)
            Text("校准页暂时无法载入")
                .font(.title3.bold())
            Text(errorMessage ?? "请稍后再试。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("重新载入") {
                Task { await prepare(force: true) }
            }
            .buttonStyle(.dsAction(.secondary, fullWidth: false))
        }
        .padding(DSSpacing.lg)
    }

    private func informationRow(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(Color.dsSkyDeep)
                .frame(width: 34, height: 34)
                .background(Color.dsSky.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DSSpacing.sm)
    }

    private func levelSelectionButton(
        title: String,
        detail: String,
        recommendedLevel: DifficultyLevel?
    ) -> some View {
        Button {
            openLevelSelection()
        } label: {
            HStack(spacing: DSSpacing.md) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.dsSkyDeep)
                    .frame(width: 42, height: 42)
                    .background(Color.dsSky.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(selectedLevel.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DSSpacing.xs)
                VStack(alignment: .trailing, spacing: 5) {
                    if recommendedLevel == selectedLevel {
                        Text("测试建议")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.dsSkyDeep)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .placementGlassPanel(padding: 0, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，当前选择 \(selectedLevel.displayName)")
        .accessibilityHint("打开全部英语水平列表")
    }

    private func openLevelSelection() {
        levelSelectionReturnPhase = phase == .result ? .result : .introduction
        withAnimation(reduceMotion ? nil : .snappy) {
            phase = .levelSelection
        }
    }

    private func closeLevelSelection() {
        withAnimation(reduceMotion ? nil : .snappy) {
            phase = levelSelectionReturnPhase
        }
    }

    private func optionButton(
        _ text: String,
        originalIndex: Int
    ) -> some View {
        let isSelected = selectedOriginalIndex == originalIndex
        return Button {
            select(originalIndex)
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Text(optionLetter(for: originalIndex))
                    .font(.caption.bold())
                    .foregroundStyle(isSelected ? .white : Color.dsSkyDeep)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? Color.dsSky : Color.dsSky.opacity(0.1), in: Circle())
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(isSelected ? Color.dsSky.opacity(0.14) : Color.clear)
            .placementGlassPanel(padding: 0, interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(
            selectedOriginalIndex != nil
                || (currentQuestion?.skill == .listening && listeningPlayCount == 0)
        )
    }

    private func skillResultRow(_ result: PlacementSkillResult) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Label(result.skill.displayName, systemImage: skillIcon(result.skill))
                .font(.subheadline.weight(.semibold))
                .frame(width: 118, alignment: .leading)
            ProgressView(value: result.accuracy)
                .tint(.dsSky)
            Text("\(result.correct)/\(result.total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func prepareIfNeeded() async {
        guard questions.isEmpty else { return }
        await prepare(force: false)
    }

    private func prepare(force: Bool) async {
        if force {
            questions = []
            engine = nil
            questionBankError = nil
            phase = .loading
        }
        do {
            let profile = try await deps.economyStore.profile()
            currentLevel = profile.difficultyLevel
            selectedLevel = profile.difficultyLevel
            do {
                questions = try PlacementQuestionBank.load(from: deps.questionBankURL)
                engine = AdaptivePlacementEngine(priorLevel: profile.difficultyLevel)
                questionBankError = nil
            } catch {
                questions = []
                engine = nil
                questionBankError = "测试题库暂时无法载入，你仍可直接选择并应用水平。"
            }
            errorMessage = nil
            #if DEBUG
            let initialPhase: Phase =
                ProcessInfo.processInfo.environment["UI_TEST_PLACEMENT_LEVEL_SELECTION"] == "1"
                    ? .levelSelection
                    : .introduction
            #else
            let initialPhase: Phase = .introduction
            #endif
            withAnimation(reduceMotion ? nil : .snappy) {
                phase = initialPhase
            }
        } catch {
            errorMessage = "学习档案暂时无法载入，请稍后再试。"
            phase = .failure
        }
    }

    private func start() {
        guard let engine,
              let question = engine.nextQuestion(in: questions)
        else { return }
        currentQuestion = question
        optionOrder = Array(question.options.indices).shuffled()
        selectedOriginalIndex = nil
        listeningPlayCount = 0
        withAnimation(reduceMotion ? nil : .snappy) {
            phase = .question
        }
    }

    private func select(_ originalIndex: Int) {
        guard selectedOriginalIndex == nil,
              let question = currentQuestion,
              var updatedEngine = engine
        else { return }
        selectedOriginalIndex = originalIndex
        Haptics.impact(.light)
        Task { await deps.speech.stopSpeaking() }

        Task {
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(220))
            }
            updatedEngine.record(question: question, selectedIndex: originalIndex)
            engine = updatedEngine
            if updatedEngine.shouldStop
                || updatedEngine.nextQuestion(in: questions) == nil
            {
                result = updatedEngine.result()
                selectedLevel = result?.difficultyLevel ?? currentLevel
                await deps.speech.stopSpeaking()
                withAnimation(reduceMotion ? nil : .snappy) {
                    phase = .result
                }
                return
            }
            guard let next = updatedEngine.nextQuestion(in: questions) else { return }
            withAnimation(reduceMotion ? nil : .snappy) {
                currentQuestion = next
                optionOrder = Array(next.options.indices).shuffled()
                selectedOriginalIndex = nil
                listeningPlayCount = 0
            }
        }
    }

    private func playListeningQuestion(_ question: PlacementQuestion) {
        guard PlacementListeningPolicy.canPlay(currentCount: listeningPlayCount),
              let audioText = question.audioText,
              let audioLanguage = question.audioLanguage
        else { return }
        listeningPlayCount += 1
        Haptics.impact(.light)
        Task {
            await deps.speech.speak(audioText, language: audioLanguage)
        }
    }

    private func applySelectedLevel(testResult: PlacementResult?) {
        let level = selectedLevel
        isApplying = true
        errorMessage = nil
        Task {
            do {
                let updated = try await deps.profileCommands.updateProfile { profile in
                    profile.difficultyLevel = level
                    profile.proficiencySource = testResult?.difficultyLevel == level
                        ? .placement
                        : .selfReported
                    if let testResult {
                        profile.placementScore = testResult.score
                        profile.placementCompletedAt = .now
                    }
                }
                isApplying = false
                Haptics.notify(.success)
                onComplete(updated)
            } catch {
                isApplying = false
                errorMessage = "所选英语水平暂时保存失败，请再试一次。"
            }
        }
    }

    private func skillIcon(_ skill: PlacementSkill) -> String {
        switch skill {
        case .vocabulary: "textformat.abc"
        case .grammar: "character.cursor.ibeam"
        case .reading: "doc.text"
        case .listening: "headphones"
        }
    }

    private func optionLetter(for originalIndex: Int) -> String {
        guard let presentedIndex = optionOrder.firstIndex(of: originalIndex) else { return "" }
        return String(UnicodeScalar(65 + presentedIndex)!)
    }
}

private struct DifficultyLevelSelectionPage: View {
    @Binding var selection: DifficultyLevel
    let currentLevel: DifficultyLevel
    let recommendedLevel: DifficultyLevel?
    let onDone: () -> Void

    private let groups: [(String, [DifficultyLevel])] = [
        ("启蒙", [.kindergarten]),
        ("小学", [.primary1, .primary2, .primary3, .primary4, .primary5, .primary6]),
        ("初中", [.junior1, .junior2, .junior3]),
        ("高中", [.senior1, .senior2, .senior3]),
        ("大学与进阶", [.undergraduate, .postgraduate, .advanced]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("选择适合你的对话难度")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("这是应用内的学习设置，不会请求通知或其他系统权限。测试建议仅供参考，之后仍可修改。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(groups, id: \.0) { title, levels in
                    levelGroup(title: title, levels: levels)
                }
            }
            .frame(maxWidth: 560)
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity)
        }
        .placementScrollEdgeBlend()
        .placementBottomBar {
            VStack(spacing: 4) {
                Text("已选择：\(selection.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("完成") { onDone() }
                    .buttonStyle(.dsActionPrimary)
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.sm)
            .frame(maxWidth: .infinity)
        }
    }

    private func levelGroup(title: String, levels: [DifficultyLevel]) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, DSSpacing.xs)

            VStack(spacing: 4) {
                ForEach(levels, id: \.rawValue) { level in
                    levelRow(level)
                }
            }
            .placementGlassPanel(padding: 4)
        }
    }

    private func levelRow(_ level: DifficultyLevel) -> some View {
        let isSelected = level == selection
        return Button {
            selection = level
            Haptics.impact(.light)
        } label: {
            HStack(spacing: DSSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Text(level.cseReference)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: DSSpacing.xs)
                if level == currentLevel {
                    levelBadge("当前", color: .secondary)
                }
                if level == recommendedLevel {
                    levelBadge("建议", color: .dsSkyDeep)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.dsSky : Color.dsBorder)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                isSelected ? Color.dsSky.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func levelBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: Capsule())
    }
}

private struct PlacementCanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark
                ? Color(red: 0.035, green: 0.09, blue: 0.14)
                : Color(red: 0.925, green: 0.978, blue: 1.0))

            LinearGradient(
                stops: [
                    .init(color: Color.dsSky.opacity(colorScheme == .dark ? 0.22 : 0.18), location: 0),
                    .init(color: Color.dsCyan.opacity(colorScheme == .dark ? 0.11 : 0.08), location: 0.5),
                    .init(color: Color.dsBrandCream.opacity(colorScheme == .dark ? 0.08 : 0.5), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.dsBrandCoral.opacity(0.08), .clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 430
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private extension View {
    @ViewBuilder
    func placementTopBar<Bar: View>(
        @ViewBuilder content: () -> Bar
    ) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0, content: content)
        } else {
            VStack(spacing: 0) {
                content()
                self
            }
        }
    }

    @ViewBuilder
    func placementBottomBar<Bar: View>(
        @ViewBuilder content: () -> Bar
    ) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, spacing: 0, content: content)
        } else {
            VStack(spacing: 0) {
                self
                content()
            }
        }
    }

    @ViewBuilder
    func placementScrollEdgeBlend() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            self
        }
    }

    func placementGlassPanel(
        padding: CGFloat = DSSpacing.md,
        interactive: Bool = false
    ) -> some View {
        self
            .padding(padding)
            .dsSceneGlass(
                radius: DSRadius.card,
                tint: Color.dsSky.opacity(0.055),
                interactive: interactive
            )
    }
}
