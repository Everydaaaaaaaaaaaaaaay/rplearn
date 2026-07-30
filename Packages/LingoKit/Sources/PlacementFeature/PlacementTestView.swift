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

/// 通常 8–10 题、最多 12 题的自适应校准。
/// 测评过程中不显示对错、不允许回退，避免后续答案被提示影响。
public struct PlacementTestView: View {
    private enum Phase {
        case loading
        case introduction
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
            LinearGradient(
                colors: [Color.dsSky.opacity(0.07), Color.dsBackground, Color.dsBackground],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Group {
                    switch phase {
                    case .loading:
                        loadingView
                    case .introduction:
                        introductionView
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
        }
        .task { await prepareIfNeeded() }
        .onDisappear {
            Task { await deps.speech.stopSpeaking() }
        }
        .interactiveDismissDisabled(phase == .question || isApplying)
    }

    private var header: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.dsSurfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isApplying)
            .accessibilityLabel("退出水平校准")

            Spacer()
            VStack(spacing: 1) {
                Text("英语水平校准")
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
        .padding(.vertical, DSSpacing.xs)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
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
                        Text("答几道题，聊得更合拍")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("题目会根据你的答案自动变难或变简单。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                VStack(spacing: 0) {
                    informationRow(
                        icon: "slider.horizontal.3",
                        title: "自适应题量",
                        detail: "通常 8–10 题，最多 12 题，约 3 分钟"
                    )
                    Divider().padding(.leading, 50)
                    informationRow(
                        icon: "headphones",
                        title: "四类能力，多种题型",
                        detail: "词汇、语法与用法、阅读、听力"
                    )
                    Divider().padding(.leading, 50)
                    informationRow(
                        icon: "lock.shield",
                        title: "没有公开排名",
                        detail: "结果只用于调整角色对话难度"
                    )
                }
                .dsSurface(.grouped, padding: 0)

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Label("凭第一感觉作答即可", systemImage: "lightbulb")
                        .font(.subheadline.weight(.semibold))
                    Text("测评中不会立即显示对错，也不能返回上一题。它是学习难度校准，不是官方证书考试。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("开始校准") {
                    start()
                }
                .buttonStyle(.dsActionPrimary)
            }
            .frame(maxWidth: 560)
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity)
        }
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
                                .dsSurface(.grouped, padding: DSSpacing.md)
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
            }
        } else {
            loadingView
        }
    }

    private func listeningCard(_ question: PlacementQuestion) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Button {
                playListeningQuestion(question)
            } label: {
                HStack(spacing: DSSpacing.sm) {
                    Image(
                        systemName: listeningPlayCount == 0
                            ? "play.circle.fill"
                            : "speaker.wave.2.circle.fill"
                    )
                    .font(.title2)
                    Text(listeningPlayCount == 0 ? "播放音频" : "再听一次")
                        .font(.headline)
                    Spacer()
                    if listeningPlayCount > 0 {
                        Text("已播放 \(listeningPlayCount) 次")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(Color.dsSkyDeep)
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .accessibilityHint("播放后即可选择答案")

            Text(
                listeningPlayCount == 0
                    ? "先听音频，再根据内容作答。"
                    : "需要时可以重听；音频文本不会显示。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .dsSurface(.grouped, padding: DSSpacing.md)
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
                        Text("建议的角色对话难度")
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
                            Label("CEFR 参考", systemImage: "globe.europe.africa")
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
                    .dsSurface(.grouped, padding: DSSpacing.lg)

                    Text(
                        "这是用于调整学习内容的短测，不是官方证书考试。"
                            + "区间较宽或稳定度有限时，应用会保守设置难度，你也可以稍后重新校准。"
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
                        applyResult(result)
                    } label: {
                        if isApplying {
                            ProgressView().tint(.white)
                        } else {
                            Text("应用这个水平")
                        }
                    }
                    .buttonStyle(.dsActionPrimary)
                    .disabled(isApplying)
                }
                .frame(maxWidth: 560)
                .padding(DSSpacing.lg)
                .frame(maxWidth: .infinity)
            }
        } else {
            loadingView
        }
    }

    private var failureView: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.dsSunset)
            Text("题目暂时无法载入")
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
            .background(
                isSelected ? Color.dsSky.opacity(0.09) : Color.dsSurface,
                in: RoundedRectangle(cornerRadius: DSRadius.card)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.card)
                    .stroke(isSelected ? Color.dsSky : Color.dsBorder, lineWidth: isSelected ? 1.5 : 1)
            }
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
            phase = .loading
        }
        do {
            async let loadedProfile = deps.economyStore.profile()
            let loadedQuestions = try PlacementQuestionBank.load(from: deps.questionBankURL)
            let profile = try await loadedProfile
            questions = loadedQuestions
            engine = AdaptivePlacementEngine(priorLevel: profile.difficultyLevel)
            errorMessage = nil
            withAnimation(reduceMotion ? nil : .snappy) {
                phase = .introduction
            }
        } catch {
            errorMessage = "随包题库校验失败，请重新安装或更新 App。"
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
        guard let audioText = question.audioText,
              let audioLanguage = question.audioLanguage
        else { return }
        listeningPlayCount += 1
        Haptics.impact(.light)
        Task {
            await deps.speech.speak(audioText, language: audioLanguage)
        }
    }

    private func applyResult(_ result: PlacementResult) {
        isApplying = true
        errorMessage = nil
        Task {
            do {
                let updated = try await deps.profileCommands.updateProfile { profile in
                    profile.difficultyLevel = result.difficultyLevel
                    profile.proficiencySource = .placement
                    profile.placementScore = result.score
                    profile.placementCompletedAt = .now
                }
                isApplying = false
                Haptics.notify(.success)
                onComplete(updated)
            } catch {
                isApplying = false
                errorMessage = "校准结果暂时保存失败，请再试一次。"
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
