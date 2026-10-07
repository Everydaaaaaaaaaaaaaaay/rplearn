import BackendKit
import AVFoundation
import CoreKit
import DesignSystem
import PersistenceKit
import SpeechKit
import SwiftUI

public struct LearningChallengeView: View {
    @State private var model: LearningChallengeModel
    @State private var audio: LearningAudioModel
    @State private var pictures: LearningImageModel
    private let character: CharacterDTO
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsExit = false
    @State private var showsHint = false
    @State private var showsTranslation = false
    @FocusState private var inputFocused: Bool
    public init(attempt: LearningAttempt, character: CharacterDTO, service: any LearningServing,
                audioSession: AudioSessionCoordinator = AudioSessionCoordinator(),
                beforePlayback: @escaping @Sendable () async -> Void = {},
                afterFinish: @escaping @Sendable () async -> Void = {}) {
        _model = State(initialValue: LearningChallengeModel(attempt: attempt, service: service, afterFinish: afterFinish)); self.character = character
        _pictures = State(initialValue: LearningImageModel(service: service))
        _audio = State(initialValue: LearningAudioModel(service: service, playback: NativeLearningAudioPlayback(session: audioSession), beforePlayback: beforePlayback))
    }
    private var theme: LearningTheme { LearningTheme(role: model.attempt.unit.roleKey) }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch model.stage {
                case .cover: cover
                case .story(let index): story(model.attempt.unit.beats[index])
                case .question: if let question = model.question { questionBody(question) }
                case .summary: summary
                }
                if let error = model.error {
                    LearningErrorBanner(message: error) { Task { await model.recover() } }
                }
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { topBar.background(.regularMaterial) }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .background(Color.dsBackground).tint(theme.tint)
        .interactiveDismissDisabled()
        .confirmationDialog("离开本次挑战？", isPresented: $showsExit, titleVisibility: .visible) {
            Button("保存进度，稍后继续") { dismiss() }
            if model.attempt.firstCompletedAt == nil && !model.hasUnconfirmedAnswer {
                Button("结束首轮，剩余题目稍后补答") {
                    Task { await model.finish(skipRemaining: true) }
                }
            }
            Button("继续挑战", role: .cancel) {}
        } message: {
            Text("已提交的答案会保留。结束首轮会重置该角色的挑战进度条，未答对的题仍可从记录补答。")
        }
        .onChange(of: model.stage) { _, _ in showsHint = false; showsTranslation = false; inputFocused = false }
        .task(id: model.question?.id) { await audio.prepare(attemptID: model.attempt.id, question: model.question) }
        .task(id: model.question?.id) { await pictures.prepare(attemptID: model.attempt.id, question: model.question) }
        .onDisappear { audio.reset(); pictures.reset() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { audio.stop(interrupted: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue {
                audio.stop(interrupted: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                audio.stop(interrupted: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .speechPlaybackDidBegin)) { notification in
            if notification.object as? UUID != audio.playbackID, audio.state == .playing { audio.stop(interrupted: true) }
        }
        .onChange(of: model.feedback?.outcome) { _, outcome in
            if outcome == .correct { Haptics.notify(.success) }
        }
        .accessibilityIdentifier("learning.challenge")
    }
    private var topBar: some View {
        HStack(spacing: 18) {
            Button { inputFocused = false; showsExit = true } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
            }.accessibilityLabel("退出挑战").disabled(model.isBusy)
            if case .story(let index) = model.stage {
                Text("开场故事").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\((model.openingBeatIndices.firstIndex(of: index) ?? 0) + 1) / \(model.openingBeatIndices.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                ProgressView(value: Double(model.attempt.round.answers.count), total: Double(max(1, model.attempt.round.questionIds.count)))
                    .tint(theme.tint).accessibilityLabel("本轮题目进度")
                Text("\(model.attempt.round.answers.count) / \(model.attempt.round.questionIds.count)")
                    .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 14).padding(.vertical, 8)
    }
    private var cover: some View {
        VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    AvatarBadge(name: character.displayName, size: 64, imageName: character.card.avatarAssetName,
                                remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)), usesPendingPlaceholder: true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(character.displayName).font(.headline)
                        Text("\(model.attempt.round.questionIds.count) 道题 · 约 \(model.attempt.unit.estimatedMinutes) 分钟")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 12)
            Label(learningLevelName(model.attempt.level), systemImage: theme.symbol)
                .font(.caption.weight(.medium)).foregroundStyle(theme.tint)
            Text(model.attempt.unit.title).font(.system(.largeTitle, design: .serif).bold())
            Text(model.attempt.unit.scene).font(.body).foregroundStyle(.secondary).lineSpacing(5)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func story(_ beat: LearningBeat) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            Label(model.attempt.unit.title, systemImage: theme.symbol).font(.caption).foregroundStyle(theme.tint)
            HStack(spacing: 12) {
            AvatarBadge(name: character.displayName, size: 48, imageName: character.card.avatarAssetName,
                        remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)), usesPendingPlaceholder: true)
                .accessibilityHidden(true)
            Text(beat.speaker).font(.subheadline.bold()).foregroundStyle(theme.tint)
            }
            Text(beat.text).font(.system(.title2, design: .serif)).lineSpacing(8).fixedSize(horizontal: false, vertical: true)
            Button { showsTranslation.toggle() } label: {
                Image(systemName: "character.bubble").frame(width: 44, height: 44)
            }.buttonStyle(.bordered)
                .accessibilityLabel(showsTranslation ? "收起中文" : "查看中文")
            if showsTranslation { Text(beat.translation).font(.body).foregroundStyle(.secondary).lineSpacing(5) }
            if dynamicTypeSize.isAccessibilitySize { skipStoryButton }
            Spacer(minLength: 24)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func questionBody(_ question: LearningQuestion) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            let headingLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout())
            headingLayout {
                Label(model.attempt.round.ordinal > 0 ? "补答 · 剩余题目" : "轮到你了", systemImage: "pencil.tip").font(.caption.bold()).foregroundStyle(theme.tint)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Text(learningLevelName(model.attempt.level)).font(.caption).foregroundStyle(.secondary)
            }
            Text(question.type == .matching && dynamicTypeSize.isAccessibilitySize ? "将两组内容逐一配对。" : question.instruction).font(.title2.bold())
            Text(question.prompt).font(.system(.title3, design: .rounded)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            if question.audio != nil {
                listeningControls(question)
            }
            if !question.imageAssetIDs.isEmpty {
                if pictures.state == .failed {
                    LearningErrorBanner(message: "图片暂时没能载入。可以重试，也可以先跳过，稍后补答。") {
                        Task { await pictures.prepare(attemptID: model.attempt.id, question: question) }
                    }.accessibilityIdentifier("learning.images.retry")
                } else if !pictures.isReady(for: question) {
                    ProgressView("正在准备图片…").font(.subheadline)
                }
            }
            answerControls(question)
                .disabled(model.isBusy || model.feedback != nil || model.hasUnconfirmedAnswer || !pictures.isReady(for: question))
            if let feedback = model.feedback {
                feedbackCard(feedback, question: question)
            } else {
                Button(showsHint ? "收起提示" : "需要一点提示？") { showsHint.toggle() }
                    .font(.subheadline).padding(.vertical, 8).disabled(model.hasUnconfirmedAnswer)
                if showsHint { Text(question.hint).font(.subheadline).foregroundStyle(.secondary) }
                if dynamicTypeSize.isAccessibilitySize && !model.hasUnconfirmedAnswer { skipQuestionButton }
            }
        }
    }
    private var audioControlTitle: String {
        switch audio.state {
        case .loading: "准备声音…"
        case .playing: "停止播放"
        case .failed: "重新载入"
        case .idle: "载入听力"
        case .ready, .interrupted: audio.hasListened ? "再听一遍" : "播放听力"
        }
    }
    private func listeningControls(_ question: LearningQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Button {
                    if audio.state == .playing { audio.stop() }
                    else if audio.state == .failed || audio.state == .idle {
                        Task { await audio.prepare(attemptID: model.attempt.id, question: question) }
                    } else { audio.play(slow: false) }
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(theme.tint.opacity(0.1))
                            if audio.state == .loading { ProgressView().tint(theme.tint) }
                            else {
                                Image(systemName: audio.state == .playing ? "stop.fill" : audio.state == .failed ? "arrow.clockwise" : "play.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(theme.tint)
                            }
                        }.frame(width: 38, height: 38).accessibilityHidden(true)
                        Text(audioControlTitle).font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if audio.hasListened {
                            Image(systemName: "checkmark.circle.fill").font(.caption)
                                .foregroundStyle(theme.tint).accessibilityHidden(true)
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(LearningPressStyle())
                    .disabled(audio.state == .loading || model.isBusy)
                    .accessibilityLabel(audioControlTitle)
                    .accessibilityHint(audio.hasListened ? "已完整听过，可以重听。" : "完整听一遍后可检查答案。")
                    .accessibilityIdentifier("learning.audio.play")
                Button { audio.play(slow: true) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "tortoise").font(.subheadline)
                        Text("慢速").font(.subheadline.weight(.medium))
                    }.foregroundStyle(theme.tint).padding(.horizontal, 10)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(LearningPressStyle())
                    .disabled(![.ready, .playing, .interrupted].contains(audio.state) || model.isBusy)
                    .accessibilityLabel("慢速播放")
                    .accessibilityHint("以四分之三速度从头播放。")
                    .accessibilityIdentifier("learning.audio.slow")
            }
            if audio.state == .failed || audio.state == .interrupted {
                Text(audio.state == .failed ? "声音暂时无法载入，请重试；也可先跳过。" : "播放已中断，轻点重听。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 2)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("learning.audio.controls")
    }
    @ViewBuilder
    private func answerControls(_ question: LearningQuestion) -> some View {
        switch question.type {
        case .choice, .listeningChoice:
            let hasPictures = !(question.options ?? []).isEmpty && (question.options ?? []).allSatisfy { $0.imageAssetId != nil }
            let columns = hasPictures && !dynamicTypeSize.isAccessibilitySize ? 2 : 1
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                ForEach(Array((question.options ?? []).enumerated()), id: \.element.id) { index, option in
                    choiceButton(option, number: index + 1)
                }
            }
        case .arrange, .audioArrange:
            VStack(alignment: .leading, spacing: 18) {
                LearningFlowLayout(spacing: 9) {
                    if model.tokens.isEmpty { Text(question.type == .audioArrange ? "按听到的顺序放入卡片" : "点选词块，组成句子").foregroundStyle(.secondary).padding(10) }
                    ForEach(Array(model.tokens.enumerated()), id: \.element) { index, id in
                        tokenButton(question.tokens?.first { $0.id == id }?.text ?? "", selected: true) { model.tokens.remove(at: index) }
                            .accessibilityLabel("第 \(index + 1) 项，\(question.tokens?.first { $0.id == id }?.text ?? "")")
                            .accessibilityHint("轻点移回备选区")
                            .accessibilityAction(named: "向前移动") { if index > 0 { model.tokens.swapAt(index, index - 1) } }
                            .accessibilityAction(named: "向后移动") { if index + 1 < model.tokens.count { model.tokens.swapAt(index, index + 1) } }
                    }
                }.frame(maxWidth: .infinity, minHeight: 80, alignment: .leading).padding(14)
                    .background(theme.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                LearningFlowLayout(spacing: 9) {
                    ForEach(question.tokens ?? []) { token in
                        tokenButton(token.text, selected: false) { model.tokens.append(token.id) }
                            .disabled(model.tokens.contains(token.id)).opacity(model.tokens.contains(token.id) ? 0.25 : 1)
                    }
                }
            }
        case .completion, .dictation:
            TextField("在这里输入英文", text: $model.text, axis: .vertical)
                .font(.title3).lineLimit(2...5).textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.asciiCapable).focused($inputFocused).padding(20)
                .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.tint.opacity(0.35)) }
                .accessibilityLabel("填写答案")
        case .matching:
            VStack(alignment: .leading, spacing: 14) {
                Text(dynamicTypeSize.isAccessibilitySize ? "先点第一组，再点第二组；再次选择可调整配对。" : "先点左侧，再点对应的右侧；再次选择可调整配对。")
                    .font(.caption).foregroundStyle(.secondary)
                let pairLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 24)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                pairLayout {
                    VStack(spacing: 12) {
                        if dynamicTypeSize.isAccessibilitySize { matchingGroupTitle("第一组") }
                        ForEach(Array((question.left ?? []).enumerated()), id: \.element.id) { index, option in
                            matchingButton(option, number: index + 1, selected: model.selectedLeft == option.id,
                                           paired: model.pairs.contains { $0.left == option.id }) { model.selectedLeft = option.id }
                        }
                    }.frame(maxWidth: .infinity)
                    VStack(spacing: 12) {
                        if dynamicTypeSize.isAccessibilitySize { matchingGroupTitle("第二组") }
                        ForEach(question.right ?? []) { option in
                            let pair = model.pairs.first { $0.right == option.id }
                            let number = pair.flatMap { p in question.left?.firstIndex { $0.id == p.left } }.map { $0 + 1 }
                            matchingButton(option, number: number, selected: false, paired: pair != nil) { model.selectPair(right: option.id) }
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }
    private func choiceButton(_ option: LearningOption, number: Int) -> some View {
        Button { model.choice = option.id } label: {
            VStack(alignment: .leading, spacing: 12) {
                if option.imageAssetId != nil { optionPicture(option).frame(height: dynamicTypeSize.isAccessibilitySize ? 200 : 132) }
                HStack(spacing: 14) {
                    Image(systemName: model.choice == option.id ? "checkmark.circle.fill" : "circle").font(.title3)
                    if option.imageAssetId == nil { Text(option.text).font(.body.weight(.medium)).multilineTextAlignment(.leading) }
                    else { Text("图片 \(number)").font(.subheadline.weight(.medium)) }
                    Spacer(minLength: 0)
                }
            }.padding(16).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .foregroundStyle(model.choice == option.id ? theme.tint : Color.primary)
                .background(model.choice == option.id ? theme.tint.opacity(0.09) : Color.dsSurface, in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(model.choice == option.id ? theme.tint : Color.primary.opacity(0.08), lineWidth: model.choice == option.id ? 2 : 1) }
        }.buttonStyle(LearningPressStyle())
            .accessibilityLabel(option.text)
            .accessibilityIdentifier("learning.option.\(option.id)")
            .accessibilityAddTraits(model.choice == option.id ? [.isSelected] : [])
    }
    private func optionPicture(_ option: LearningOption) -> some View {
        ZStack {
            Color.white
            if let id = option.imageAssetId, let image = pictures.images[id] {
                Image(uiImage: image).resizable().scaledToFit().padding(8)
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.gray.opacity(0.4))
            }
        }.clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
    }
    private func matchingGroupTitle(_ title: String) -> some View {
        Text(title).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
    private func tokenButton(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(text).font(.body.weight(.medium)).padding(.horizontal, 15).padding(.vertical, 13)
                .foregroundStyle(selected ? theme.tint : Color.primary)
                .background(Color.dsSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? theme.tint.opacity(0.5) : Color.primary.opacity(0.12)) }
        }.buttonStyle(LearningPressStyle())
    }
    private func matchingButton(_ option: LearningOption, number: Int?, selected: Bool, paired: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Text(number.map { "\($0)" } ?? "—").font(.caption.monospacedDigit().bold()).foregroundStyle(theme.tint)
                if option.imageAssetId != nil { optionPicture(option).frame(height: 132) }
                else { Text(option.text).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading) }
            }.padding(15).frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                .background(paired ? theme.tint.opacity(0.09) : Color.dsSurface, in: RoundedRectangle(cornerRadius: 15))
                .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(selected ? theme.tint : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1) }
        }.buttonStyle(LearningPressStyle()).foregroundStyle(.primary)
            .accessibilityLabel(option.text)
            .accessibilityValue(paired ? "已配对 \(number ?? 0)" : selected ? "已选中" : "未配对")
    }
    private func feedbackCard(_ grade: LearningGrade, question: LearningQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(grade.outcome == .correct ? (model.awardedPoints > 0 ? "答对了 · +\(model.awardedPoints) 点" : "答对了") : grade.outcome == .skipped ? "先留到下次" : "再认识一下这个表达",
                  systemImage: grade.outcome == .correct ? "checkmark.circle.fill" : "lightbulb")
                .font(.headline).foregroundStyle(grade.outcome == .correct ? theme.tint : Color.primary)
            if grade.outcome != .correct { Text(solutionText(grade.solution, question: question)).font(.body.bold()) }
            Text(grade.explanation).font(.subheadline).lineSpacing(4)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .combine)
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: model.attempt.remainingCount == 0 ? "checkmark.seal" : "book.closed")
                .font(.system(size: 56, weight: .light)).foregroundStyle(theme.tint).padding(.top, 28).accessibilityHidden(true)
            Text("本轮结果").font(.system(.largeTitle, design: .serif).bold())
            Text(model.attempt.unit.title).font(.title3).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text("\(model.attempt.correctQuestionIds.count)").font(.system(size: 56, weight: .semibold, design: .rounded))
                Text("/ \(model.attempt.unit.questions.count) 题已掌握").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 13) {
                Text("本轮答对 \(model.roundPoints) 题").font(.headline)
                Text("进度归入：\(learningLevelName(model.attempt.level))").font(.subheadline)
                Text(model.attempt.remainingCount > 0 ? "还有 \(model.attempt.remainingCount) 道题可以补答，获得尚未拿到的进度。" : "这份单元的进度已经全部获得。继续聊天，开启下一段不同的挑战。")
                    .font(.subheadline).foregroundStyle(.secondary)
                if model.attempt.firstCompletedAt == nil { Text("确认完成后，角色挑战条归零，重新从聊天积累。").font(.caption).foregroundStyle(.secondary) }
            }.modifier(LearningPaper())
            if model.attempt.firstCompletedAt != nil && model.attempt.remainingCount > 0 {
                Button("补答剩余题目") { Task { await model.retry() } }.font(.headline).padding(.vertical, 12).disabled(model.isBusy)
            }
        }
    }
    private var bottomBar: some View {
        VStack(spacing: 10) {
            switch model.stage {
            case .cover:
                primary("开始故事") { model.advance() }
            case .story:
                primary(model.isLastOpeningBeat ? "开始答题" : "继续故事") { model.advance() }
                if !dynamicTypeSize.isAccessibilitySize { skipStoryButton }
            case .question:
                if model.feedback != nil { primary("继续") { model.advance() } }
                else if model.hasUnconfirmedAnswer { primary("重新确认提交") { Task { await model.submit() } } }
                else {
                    primary("检查", disabled: model.answer == nil || !pictures.isReady(for: model.question) || (model.question?.audio != nil && !audio.hasListened)) { inputFocused = false; audio.stop(); Task { await model.submit() } }
                    if !dynamicTypeSize.isAccessibilitySize { skipQuestionButton }
                }
            case .summary:
                if model.attempt.firstCompletedAt == nil { primary("完成本轮挑战") { Task { await model.finish() } } }
                else { primary("回到学习页") { dismiss() } }
            }
        }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12).frame(maxWidth: 680).frame(maxWidth: .infinity)
            .background(.regularMaterial)
    }
    private var skipQuestionButton: some View {
        Button("暂时跳过，留待补答") { inputFocused = false; audio.stop(); Task { await model.submit(skip: true) } }
            .font(.subheadline).padding(8).disabled(model.isBusy)
    }
    private var skipStoryButton: some View {
        Button("直接开始题目") { model.skipStory() }.font(.subheadline).padding(8)
    }
    private func primary(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        LearningPrimaryButton(title: title, tint: theme.tint, busy: model.isBusy, disabled: disabled, action: action)
    }
    private func solutionText(_ answer: LearningAnswer, question: LearningQuestion) -> String {
        switch answer.kind {
        case .choice: return question.options?.first { $0.id == answer.optionId }?.text ?? ""
        case .arrange: return (answer.tokenIds ?? []).compactMap { id in question.tokens?.first { $0.id == id }?.text }.joined(separator: " ")
        case .text: return answer.text ?? ""
        case .matching: return (answer.pairs ?? []).map { pair in
            "\(question.left?.first { $0.id == pair.left }?.text ?? "") ↔ \(question.right?.first { $0.id == pair.right }?.text ?? "")"
        }.joined(separator: "\n")
        case .skip: return ""
        }
    }
}

/// 词块按阅读顺序换行，每块保留独立身份，重复词也能操作。
struct LearningFlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 320, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = arrange(width: bounds.width, subviews: subviews).positions
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + positions[index].x, y: bounds.minY + positions[index].y), anchor: .topLeading,
                       proposal: ProposedViewSize(width: min(view.sizeThatFits(.unspecified).width, bounds.width), height: nil))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0; var positions: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: min(view.sizeThatFits(.unspecified).width, width), height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            positions.append(CGPoint(x: x, y: y)); x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), positions)
    }
}
