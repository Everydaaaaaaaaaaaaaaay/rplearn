import DesignSystem
import DomainKit
import PersistenceKit
import SwiftUI

/// 按当前能力自评的英语起点；学段和考试名仅帮助识别语言难度，不代表学历或证书。
public enum SelfAssessedEnglishLevel: String, CaseIterable, Identifiable, Sendable {
    case starting
    case foundation
    case everyday
    case independent
    case confident
    case proficient
    case advanced

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .starting: "入门起步"
        case .foundation: "小学英语水平"
        case .everyday: "初中英语水平"
        case .independent: "高中英语水平"
        case .confident: "英语四级水平"
        case .proficient: "英语六级水平"
        case .advanced: "雅思进阶水平"
        }
    }

    public var description: String {
        switch self {
        case .starting: "认识少量单词，需要从短句开始"
        case .foundation: "能理解常见短句，表达还需要提示"
        case .everyday: "能进行简单日常交流，读懂基础短文"
        case .independent: "能读懂一般文章，表达经历和简单观点"
        case .confident: "能应对多数日常话题，理解较长的英语文章"
        case .proficient: "能理解较复杂文章，较清楚地讨论观点和细节"
        case .advanced: "能理解长篇材料，较自如地讨论复杂话题"
        }
    }

    public var difficultyLevel: DifficultyLevel {
        switch self {
        case .starting: .primary3
        case .foundation: .primary6
        case .everyday: .junior3
        case .independent: .senior3
        case .confident: .undergraduate
        case .proficient: .postgraduate
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
        case .postgraduate:
            .proficient
        case .advanced:
            .advanced
        }
    }
}

/// 剧情开始前的轻量学习档案：昵称、使用目标与当前英语水平。
struct LearnerProfileSetupView: View {
    private enum Step: Int, CaseIterable {
        case nickname
        case goal
        case level

        var title: String {
            switch self {
            case .nickname: "先认识一下你"
            case .goal: "你最想用英语做什么？"
            case .level: "当前英语水平"
            }
        }

        var subtitle: String {
            switch self {
            case .nickname: "角色会用这个名字称呼你"
            case .goal: "可多选，我们会优先安排相关话题和表达"
            case .level: "按你现在的英语能力选择，之后可以测评调整"
            }
        }
    }

    let initialProfile: UserProfileDTO
    let profileCommands: any ProfileCommandGateway
    let onComplete: (UserProfileDTO) -> Void

    @State private var step: Step = .nickname
    @State private var nickname: String
    @State private var goals: [LearningGoal]
    @State private var level: SelfAssessedEnglishLevel?
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
        _goals = State(initialValue: initialProfile.hasCompletedProfileSetup ? initialProfile.learningGoals : [])
        _level = State(initialValue: initialProfile.hasCompletedProfileSetup
            ? SelfAssessedEnglishLevel.closest(to: initialProfile.difficultyLevel) : nil)
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
        .background(Puff.Palette.page)
        .overlay(alignment: .bottom) { Rectangle().fill(Puff.Palette.line).frame(height: 1) }
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
                    isSelected: goals.contains(item),
                    allowsMultipleSelection: true
                ) {
                    if goals.contains(item) {
                        goals.removeAll { $0 == item }
                    } else {
                        goals.append(item)
                    }
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.title)，\(item.description)")
                .accessibilityValue(level == item ? "已选择" : "未选择")
                .accessibilityAddTraits(level == item ? [.isButton, .isSelected] : .isButton)
                .accessibilityRemoveTraits(level == item ? [] : .isSelected)
            }
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
                    if step == .level {
                        save()
                    } else {
                        advance()
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(step == .level ? "保存并开始测评" : "继续")
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
        .background(Puff.Palette.page)
        .overlay(alignment: .top) { Rectangle().fill(Puff.Palette.line).frame(height: 1) }
    }

    private var canContinue: Bool {
        switch step {
        case .nickname:
            !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .goal:
            !goals.isEmpty
        case .level:
            level != nil
        }
    }

    private func selectionTile(
        title: String,
        systemImage: String,
        isSelected: Bool,
        allowsMultipleSelection: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.dsSkyDeep : .secondary)
                    Spacer()
                    selectionIndicator(isSelected: isSelected, allowsMultipleSelection: allowsMultipleSelection)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityRemoveTraits(isSelected ? [] : .isSelected)
    }

    private func selectionIndicator(isSelected: Bool, allowsMultipleSelection: Bool = false) -> some View {
        Image(systemName: allowsMultipleSelection
            ? (isSelected ? "checkmark.square.fill" : "square")
            : (isSelected ? "checkmark.circle.fill" : "circle"))
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
        guard !goals.isEmpty, let level else { return }
        let selectedGoals = goals
        let normalizedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let updated = try await profileCommands.updateProfile { profile in
                    profile.displayName = normalizedNickname
                    profile.difficultyLevel = level.difficultyLevel
                    profile.learningGoals = selectedGoals
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
}
