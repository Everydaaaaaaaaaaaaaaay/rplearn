import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 面向用户的粗粒度自评档位。它描述“能做什么”，避免要求新用户理解考试分数。
public enum SelfAssessedEnglishLevel: String, CaseIterable, Identifiable, Sendable {
    case starting
    case foundation
    case everyday
    case independent
    case confident
    case advanced

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .starting: "刚刚开始"
        case .foundation: "有一些基础"
        case .everyday: "能简单交流"
        case .independent: "能独立表达"
        case .confident: "能流畅讨论"
        case .advanced: "接近专业使用"
        }
    }

    public var description: String {
        switch self {
        case .starting: "认识少量单词，需要从短句开始"
        case .foundation: "能理解常见句子，表达还需要提示"
        case .everyday: "能处理熟悉话题，偶尔会停顿或出错"
        case .independent: "能讲经历和观点，也能读一般文章"
        case .confident: "多数场景交流自然，能讨论复杂话题"
        case .advanced: "表达准确灵活，能理解含蓄和细微差别"
        }
    }

    public var difficultyLevel: DifficultyLevel {
        switch self {
        case .starting: .primary3
        case .foundation: .primary6
        case .everyday: .junior3
        case .independent: .senior3
        case .confident: .undergraduate
        case .advanced: .advanced
        }
    }

    public static func closest(to difficulty: DifficultyLevel) -> Self {
        switch difficulty {
        case .kindergarten, .primary1, .primary2, .primary3:
            .starting
        case .primary4, .primary5, .primary6:
            .foundation
        case .junior1, .junior2, .junior3:
            .everyday
        case .senior1, .senior2, .senior3:
            .independent
        case .undergraduate:
            .confident
        case .postgraduate, .advanced:
            .advanced
        }
    }
}

/// 剧情开始前的轻量学习档案。前三项必填，学段可跳过。
struct LearnerProfileSetupView: View {
    private enum Step: Int, CaseIterable {
        case nickname
        case goal
        case level
        case stage

        var title: String {
            switch self {
            case .nickname: "先认识一下你"
            case .goal: "你最想用英语做什么？"
            case .level: "现在使用英语是什么感觉？"
            case .stage: "最后一项，可选"
            }
        }

        var subtitle: String {
            switch self {
            case .nickname: "角色会用这个名字称呼你"
            case .goal: "我们会优先安排相关话题和表达"
            case .level: "选最接近的一项就好，之后还可以测一测"
            case .stage: "学段只帮助我们选择更贴近你的情境"
            }
        }
    }

    let initialProfile: UserProfileDTO
    let profileCommands: any ProfileCommandGateway
    let onComplete: (UserProfileDTO) -> Void

    @State private var step: Step = .nickname
    @State private var nickname: String
    @State private var goal: LearningGoal?
    @State private var level: SelfAssessedEnglishLevel?
    @State private var stage: StudyStage?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var nicknameIsFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        initialProfile: UserProfileDTO,
        profileCommands: any ProfileCommandGateway,
        onComplete: @escaping (UserProfileDTO) -> Void
    ) {
        self.initialProfile = initialProfile
        self.profileCommands = profileCommands
        self.onComplete = onComplete
        let placeholderNames = ["旅行者", "Traveler"]
        _nickname = State(
            initialValue: placeholderNames.contains(initialProfile.displayName)
                ? "" : initialProfile.displayName
        )
        _goal = State(initialValue: nil)
        _level = State(initialValue: nil)
        _stage = State(initialValue: initialProfile.studyStage)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.dsSky.opacity(0.09), Color.dsBackground, Color.dsBackground],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    stepContent
                        .frame(maxWidth: 560)
                        .padding(.horizontal, DSSpacing.lg)
                        .padding(.top, DSSpacing.lg)
                        .padding(.bottom, 112)
                        .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        .animation(reduceMotion ? nil : .snappy, value: step)
        .onChange(of: nickname) { _, value in
            if value.count > 20 {
                nickname = String(value.prefix(20))
            }
        }
        .onAppear {
            if step == .nickname {
                nicknameIsFocused = nickname.isEmpty
            }
        }
    }

    private var header: some View {
        VStack(spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "airplane.departure")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.dsSkyDeep)
                Text("咕游记 · 学习卡")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.dsSkyDeep)
                Spacer()
                Text("开始旅程 1 / 3")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.dsSky : Color.dsBorder)
                        .frame(height: 4)
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var stepContent: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(step.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            switch step {
            case .nickname:
                nicknameStep
            case .goal:
                goalStep
            case .level:
                levelStep
            case .stage:
                stageStep
            }
        }
        .id(step)
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                )
        )
    }

    private var nicknameStep: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                BrandMascotView(pose: .greeting, size: 88, showsShadow: false)
                Text("在城市剧情和真实感对话里，把学过的英语真正用起来。我会帮你找到合适的旅伴。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("你的昵称")
                    .font(.subheadline.weight(.semibold))
                TextField("例如：小雨", text: $nickname)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($nicknameIsFocused)
                    .onSubmit {
                        guard canContinue else { return }
                        advance()
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .frame(minHeight: 52)
                    .background(Color.dsSurfaceMuted, in: RoundedRectangle(cornerRadius: DSRadius.inline))
                    .overlay {
                        RoundedRectangle(cornerRadius: DSRadius.inline)
                            .stroke(
                                nicknameIsFocused ? Color.dsSky : Color.dsBorder,
                                lineWidth: nicknameIsFocused ? 1.5 : 1
                            )
                    }
                Text("最多 20 个字符，只会用于 App 内称呼")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .dsSurface(.grouped, padding: DSSpacing.lg)
    }

    private var goalStep: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: DSSpacing.sm
        ) {
            ForEach(LearningGoal.allCases, id: \.rawValue) { item in
                selectionTile(
                    title: item.displayName,
                    systemImage: goalIcon(item),
                    isSelected: goal == item
                ) {
                    goal = item
                }
            }
        }
    }

    private var levelStep: some View {
        VStack(spacing: DSSpacing.sm) {
            ForEach(SelfAssessedEnglishLevel.allCases) { item in
                Button {
                    level = item
                } label: {
                    HStack(spacing: DSSpacing.sm) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(item.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: DSSpacing.xs)
                        selectionIndicator(isSelected: level == item)
                    }
                    .padding(DSSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        level == item ? Color.dsSky.opacity(0.1) : Color.dsSurface,
                        in: RoundedRectangle(cornerRadius: DSRadius.card)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: DSRadius.card)
                            .stroke(level == item ? Color.dsSky : Color.dsBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(level == item ? .isSelected : [])
            }
        }
    }

    private var stageStep: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: DSSpacing.sm
            ) {
                ForEach(StudyStage.allCases, id: \.rawValue) { item in
                    selectionTile(
                        title: item.displayName,
                        systemImage: stageIcon(item),
                        isSelected: stage == item
                    ) {
                        stage = item
                    }
                }
            }

            Button {
                stage = nil
            } label: {
                HStack {
                    Text("暂不填写")
                    Spacer()
                    selectionIndicator(isSelected: stage == nil)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(DSSpacing.md)
                .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: DSRadius.inline))
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.inline)
                        .stroke(stage == nil ? Color.dsSky : Color.dsBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            Label("以后可在“我的”里修改；英语水平也可以随时重新校准。", systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(spacing: DSSpacing.xs) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.dsDanger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: DSSpacing.sm) {
                if step != .nickname {
                    Button("上一步") {
                        goBack()
                    }
                    .buttonStyle(.dsAction(.secondary, fullWidth: false))
                    .disabled(isSaving)
                }

                Button {
                    if step == .stage {
                        save()
                    } else {
                        advance()
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(step == .stage ? "保存并认识咕咕" : "继续")
                    }
                }
                .buttonStyle(.dsActionPrimary)
                .disabled(!canContinue || isSaving)
                .opacity(canContinue || isSaving ? 1 : 0.45)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.top, DSSpacing.sm)
        .padding(.bottom, DSSpacing.xs)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var canContinue: Bool {
        switch step {
        case .nickname:
            !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .goal:
            goal != nil
        case .level:
            level != nil
        case .stage:
            true
        }
    }

    private func selectionTile(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.dsSkyDeep : .secondary)
                    Spacer()
                    selectionIndicator(isSelected: isSelected)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
            .background(
                isSelected ? Color.dsSky.opacity(0.1) : Color.dsSurface,
                in: RoundedRectangle(cornerRadius: DSRadius.card)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.card)
                    .stroke(isSelected ? Color.dsSky : Color.dsBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.body)
            .foregroundStyle(isSelected ? Color.dsSky : Color.dsBorder)
    }

    private func advance() {
        guard canContinue,
              let next = Step(rawValue: step.rawValue + 1)
        else { return }
        errorMessage = nil
        nicknameIsFocused = false
        withAnimation(reduceMotion ? nil : .snappy) {
            step = next
        }
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        errorMessage = nil
        withAnimation(reduceMotion ? nil : .snappy) {
            step = previous
        }
    }

    private func save() {
        guard let goal, let level else { return }
        let normalizedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedStage = stage
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let updated = try await profileCommands.updateProfile { profile in
                    profile.displayName = normalizedNickname
                    profile.difficultyLevel = level.difficultyLevel
                    profile.learningGoal = goal
                    profile.studyStage = selectedStage
                    profile.proficiencySource = .selfReported
                    profile.placementScore = nil
                    profile.placementCompletedAt = nil
                    profile.hasCompletedProfileSetup = true
                }
                isSaving = false
                onComplete(updated)
            } catch {
                isSaving = false
                errorMessage = "学习卡暂时保存失败，请再试一次。"
            }
        }
    }

    private func goalIcon(_ goal: LearningGoal) -> String {
        switch goal {
        case .dailyConversation: "bubble.left.and.bubble.right"
        case .travel: "airplane"
        case .school: "books.vertical"
        case .exam: "checkmark.seal"
        case .studyAbroad: "graduationcap"
        case .work: "briefcase"
        case .culture: "person.2"
        }
    }

    private func stageIcon(_ stage: StudyStage) -> String {
        switch stage {
        case .primary: "pencil"
        case .juniorHigh, .seniorHigh: "backpack"
        case .university, .postgraduate: "graduationcap"
        case .working: "briefcase"
        case .other: "person"
        }
    }
}
