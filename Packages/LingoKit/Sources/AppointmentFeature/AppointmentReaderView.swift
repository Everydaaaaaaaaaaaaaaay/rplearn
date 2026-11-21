import BackendKit
import CoreKit
import DesignSystem
import DictKit
import SpeechKit
import SwiftUI

struct AppointmentReaderView: View {
    @Bindable var model: AppointmentModel
    let readingServices: AppointmentReadingServices?
    let characterName: (UUID) -> String
    let onChat: (UUID) -> Void
    let onMemory: (UUID) -> Void
    @State private var translation = true
    @State private var history = false
    @State private var credits = false
    @State private var photoPaused = false
    @State private var summary = false
    @State private var wordSelection: TokenSelection?
    @State private var sound = false
    @State private var customSubmitActions = 0
    @State private var sendingCustomAction = false
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase

    private let ink = AppointmentStyle.ink

    var body: some View {
        Group {
            if let services = readingServices {
                reader.wordLookupOverlay(selection: $wordSelection, dictionary: services.dictionary, grammar: services.grammar, onSpeak: { word in
                    Task { await services.speech.speak(SpeechRequest(text: word, language: "en-US", purpose: .pronunciation)) }
                }, favoriteActions: WordFavoriteActions(contains: { (try? await services.favorites.isWordFavorited($0)) ?? false }, toggle: { (try? await services.favorites.toggleWord($0, translationZh: $1)) ?? false }))
            } else { reader }
        }
        .toolbar(.hidden, for: .navigationBar)
        .dsInteractivePopGesture(enabled: !inputFocused)
        .dsTabBarHidden()
        .environment(\.colorScheme, .light)
        .tint(ink)
        .sheet(isPresented: $history) { AppointmentHistoryView(detail: model.detail, characterName: characterName) }
        .sheet(isPresented: $credits) { AppointmentPhotoCreditsView(cityID: model.detail?.appointment.cityId ?? "", cityName: model.detail?.appointment.cityName ?? "") }
        .navigationDestination(isPresented: $summary) { AppointmentSummaryView(model: model, characterName: characterName, onChat: onChat, onMemory: onMemory) }
        .task(id: narrationIdentity) {
            guard let readingServices else { return }
            await readingServices.speech.stopSpeaking()
            guard canNarrate, !Task.isCancelled, let beat = model.beat,
                  let characterID = model.detail?.appointment.characterId else { return }
            let characterRequest = beat.speaker == "character"
                ? await readingServices.characterNarration(characterID, beat.english) : nil
            guard !Task.isCancelled else { return }
            let request = AppointmentNarration.request(for: beat, characterName: characterName(characterID),
                                                       characterRequest: characterRequest)
            await readingServices.speech.speakAndWait(request)
        }
        .onDisappear { Task { await readingServices?.speech.stopSpeaking(); await model.persistReading() } }
        .onChange(of: scenePhase) { _, phase in
            Task {
                if phase == .active { await model.refreshAfterConnectionFailure() }
                else { await model.persistReading() }
            }
        }
    }

    private var canNarrate: Bool {
        sound && scenePhase == .active && wordSelection == nil && !inputFocused && !history && !credits && !summary
    }

    private var narrationIdentity: String {
        "\(model.block?.id ?? "")-\(model.beatIndex)-\(canNarrate)"
    }

    private var reader: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                panel(maxHeight: geometry.size.height - 24)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: 640)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header.padding(.horizontal, 20).padding(.vertical, 4).frame(maxWidth: 640)
        }
        .background {
            AppointmentPhotoView(cityID: model.detail?.appointment.cityId ?? "", cityName: model.detail?.appointment.displayCityName ?? "", paused: photoPaused || inputFocused || history || credits || wordSelection != nil, showsControls: false)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            AppointmentBackButton(label: "暂停并返回约定") { inputFocused = false; dismiss() }
            Text(model.detail.map { $0.appointment.displayTitle(companionName: characterName($0.appointment.characterId)) } ?? "")
                .font(.subheadline.weight(.medium)).lineLimit(1)
            Spacer(minLength: 0)
            Button { inputFocused = false; history = true } label: {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44)
            }.accessibilityLabel("回看实际经历").accessibilityIdentifier("appointment.history")
                .accessibilityValue(customInputDiagnostic)
            Menu {
                if readingServices != nil { Button(sound ? "关闭朗读" : "朗读英文", systemImage: sound ? "speaker.slash" : "speaker.wave.2") { sound.toggle(); if !sound { Task { await readingServices?.speech.stopSpeaking() } } } }
                Button(photoPaused ? "继续背景轮播" : "暂停背景轮播", systemImage: "photo") { photoPaused.toggle() }
                Button("照片来源", systemImage: "info.circle") { credits = true }
                Button("暂时离开", systemImage: "pause") { dismiss() }
                if model.detail?.appointment.status == "in_progress", model.block?.ending == false {
                    Button("今天就到这里", systemImage: "leaf") { inputFocused = false; Task { await model.submit(action: .choice, finish: true) } }.disabled(!model.mayRespond || sendingCustomAction)
                }
            } label: { Image(systemName: "ellipsis").font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44) }.accessibilityLabel("阅读选项")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
    }

    private func panel(maxHeight: CGFloat) -> some View {
        let beat = model.beat
        return VStack(alignment: .leading, spacing: 0) {
            if !inputFocused {
                HStack {
                    if let beat { speakerHeader(for: beat) }
                    Spacer()
                    Button(translation ? "中 / EN" : "EN") { translation.toggle() }.font(.caption.weight(.medium)).frame(minWidth: 52, minHeight: 44).accessibilityLabel(translation ? "隐藏中文翻译" : "显示中文翻译")
                }
                Rectangle().fill(ink.opacity(0.12)).frame(height: 0.5).padding(.bottom, 18)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let beat { paragraph(beat) }
                    if model.isLastPage && model.isLatestBlock && model.block?.ending == false && model.detail?.appointment.status == "in_progress" {
                        ForEach(model.block?.choices ?? []) { choice in
                            Button { Task { await model.submit(action: .choice, choiceID: choice.id) } } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .medium)).foregroundStyle(ink.opacity(0.5))
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(choice.english).font(.subheadline.weight(.medium))
                                        if translation { Text(choice.chinese).font(.caption).opacity(0.75) }
                                    }
                                    Spacer(minLength: 0)
                                }.multilineTextAlignment(.leading).padding(16).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                    .background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(ink.opacity(0.14), lineWidth: 1))
                            }.buttonStyle(DSSceneEntranceButtonStyle()).disabled(!model.mayRespond || sendingCustomAction).accessibilityIdentifier("appointment.choice.\(choice.id)")
                        }
                    }
                    if model.submitting { ProgressView("正在继续…").tint(ink).font(.subheadline) }
                    if let error = model.error { AppointmentErrorView(message: error, loading: model.loading || model.submitting) { Task { if model.pending != nil { await model.retry() } else { await model.load() } } } }
                    else if model.pending != nil && !model.loading && !model.submitting { Text("上次回应已保留。"); Button("重试原回应") { Task { await model.retry() } } }
                    if showsComposer { customActionInput }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(inputFocused ? .bottom : .top, for: .sizeChanges)
            .frame(maxHeight: max(44, maxHeight - (inputFocused ? 48 : 144)))
            .fixedSize(horizontal: false, vertical: !dynamicTypeSize.isAccessibilitySize)
            .accessibilityIdentifier("appointment.readerScroll")
            .id("\(model.block?.id ?? "")-\(model.beatIndex)")
            if !inputFocused {
                HStack {
                    if readingServices != nil { Text("轻点英文可查词").font(.caption2).foregroundStyle(ink.opacity(0.6)) }
                    Spacer()
                    if model.isLastPage && model.isLatestBlock && model.block?.ending == true {
                        Button("查看这次回顾") { summary = true }.font(.subheadline.weight(.semibold)).frame(minHeight: 48).accessibilityIdentifier("appointment.summary")
                    } else if !model.isLastPage || !model.isLatestBlock {
                        Button { wordSelection = nil; Task { await model.advance() } } label: { Label("继续", systemImage: "arrow.right").font(.subheadline.weight(.medium)).frame(minWidth: 72, minHeight: 44) }.accessibilityIdentifier("appointment.next")
                    }
                }.padding(.top, 8)
            }
        }
        .foregroundStyle(ink).padding(24)
        .background((reduceTransparency || contrast == .increased ? AppointmentStyle.canvas : AppointmentStyle.canvas.opacity(0.96)), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.7)))
        .environment(\.colorScheme, .light)
    }

    private func speakerHeader(for beat: BackendAppointmentBeat) -> some View {
        let characterID = beat.speaker == "character" ? model.detail?.appointment.characterId : nil
        let name = characterID.map(characterName) ?? "Narrator"
        return HStack(spacing: 8) {
            Group {
                if let characterID {
                    AppointmentAvatarView(characterID: characterID, name: name, size: 32)
                } else {
                    AvatarBadge(name: "旁", tint: ink, size: 32)
                }
            }
            .accessibilityHidden(true)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink.opacity(0.8))
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("appointment.speaker")
        }
    }

    private func paragraph(_ beat: BackendAppointmentBeat) -> some View {
        let paragraphID = "appointment-\(model.block?.id ?? "")-\(model.beatIndex)"
        return VStack(alignment: .leading, spacing: 16) {
            if readingServices != nil {
                TappableText(tokens: TokenCache.tokens(for: beat.english, cacheKey: paragraphID),
                             contextID: "\(model.id)-\(paragraphID)", textColor: ink,
                             selection: wordSelection, onSelect: { wordSelection = $0 })
                    .font(.body).lineSpacing(6).accessibilityIdentifier("appointment.line")
            } else {
                Text(beat.english).font(.body).lineSpacing(6).textSelection(.enabled)
                    .accessibilityIdentifier("appointment.line")
            }
            if translation {
                Text(beat.chinese).font(.subheadline).foregroundStyle(ink.opacity(0.77))
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("appointment.translation.\(paragraphID)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsComposer: Bool {
        model.isLastPage && model.isLatestBlock && model.block?.ending == false && model.detail?.appointment.status == "in_progress"
    }

    private var canSubmitCustomAction: Bool {
        model.mayRespond && !sendingCustomAction && !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.draft.count <= 500
    }

    private var customActionInput: some View {
        AppointmentCustomActionInput(model: model, inputFocused: $inputFocused,
            sendingCustomAction: sendingCustomAction, submitCustomAction: submitCustomAction)
    }

    private func submitCustomAction() {
        guard canSubmitCustomAction else { return }
        let input = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        customSubmitActions += 1
        sendingCustomAction = true
        inputFocused = false
        Task {
            await model.submit(action: .choice, input: input)
            sendingCustomAction = false
        }
    }

    private var customInputDiagnostic: String {
        #if DEBUG
        "customSubmitActions:\(customSubmitActions);focused:\(inputFocused)"
        #else
        ""
        #endif
    }
}
