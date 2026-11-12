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
    @State private var customInput = false
    @State private var queuedCustomInput: String?
    @State private var history = false
    @State private var credits = false
    @State private var photoPaused = false
    @State private var summary = false
    @State private var wordSelection: TokenSelection?
    @State private var sound = false
    @State private var customSubmitActions = 0
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase

    private let ink = Color(red: 0.13, green: 0.19, blue: 0.18)
    private let paper = Color(red: 0.98, green: 0.96, blue: 0.90)
    private let gold = Color(red: 0.84, green: 0.68, blue: 0.40)

    var body: some View {
        Group {
            if let services = readingServices {
                reader.wordLookupOverlay(selection: $wordSelection, dictionary: services.dictionary, grammar: services.grammar, onSpeak: { word in
                    Task { await services.speech.speak(SpeechRequest(text: word, language: "en-US", purpose: .pronunciation)) }
                }, favoriteActions: WordFavoriteActions(contains: { (try? await services.favorites.isWordFavorited($0)) ?? false }, toggle: { (try? await services.favorites.toggleWord($0, translationZh: $1)) ?? false }))
            } else { reader }
        }
        .navigationBarHidden(true).dsTabBarHidden()
        .environment(\.colorScheme, .dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $customInput, onDismiss: completeCustomInputDismissal) { inputSheet }
        .sheet(isPresented: $history) { AppointmentHistoryView(detail: model.detail, characterName: characterName) }
        .sheet(isPresented: $credits) { AppointmentPhotoCreditsView(cityID: model.detail?.appointment.cityId ?? "", cityName: model.detail?.appointment.cityName ?? "") }
        .navigationDestination(isPresented: $summary) { AppointmentSummaryView(model: model, characterName: characterName, onChat: onChat, onMemory: onMemory) }
        .task(id: narrationIdentity) {
            guard let readingServices else { return }
            await readingServices.speech.stopSpeaking()
            guard canNarrate, let beat = model.beat, let characterID = model.detail?.appointment.characterId else { return }
            let characterRequest = beat.speaker == "character"
                ? await readingServices.characterNarration(characterID, beat.english) : nil
            guard !Task.isCancelled else { return }
            let request = AppointmentNarration.request(for: beat, characterName: characterName(characterID),
                                                      characterRequest: characterRequest)
            await readingServices.speech.speakAndWait(request)
        }
        .onDisappear { Task { await readingServices?.speech.stopSpeaking(); await model.persistReading() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { Task { await model.persistReading() } } }
    }

    private var canNarrate: Bool {
        sound && scenePhase == .active && wordSelection == nil && !customInput && !history && !credits && !summary
    }

    private var narrationIdentity: String {
        "\(model.block?.id ?? "")-\(model.beatIndex)-\(canNarrate)"
    }

    private var reader: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 12)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(model.detail?.appointment.title ?? "这次相处")
                            .font(.system(.title, design: .serif).weight(.medium)).multilineTextAlignment(.center)
                            .foregroundStyle(paper).shadow(radius: 8).padding(.bottom, 20)
                    }
                    panel(maxHeight: geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.84 : 0.60))
                }.padding(.horizontal, 18).padding(.bottom, 12).padding(.top, 4)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background {
                AppointmentPhotoView(cityID: model.detail?.appointment.cityId ?? "", cityName: model.detail?.appointment.cityName ?? "", paused: photoPaused || customInput || history || credits || wordSelection != nil, showsControls: false).ignoresSafeArea()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("暂停并返回约定")
            VStack(alignment: .leading, spacing: 4) {
                Text(model.detail?.appointment.cityName ?? "赴约").font(.caption)
                Text(model.block?.location ?? "这次相处").font(.subheadline.weight(.semibold)).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button { history = true } label: { Image(systemName: "clock.arrow.circlepath").frame(width: 44, height: 44) }.accessibilityLabel("回看实际经历").accessibilityIdentifier("appointment.history")
                .accessibilityValue(customInputDiagnostic)
            Menu {
                if readingServices != nil { Button(sound ? "关闭朗读" : "朗读英文", systemImage: sound ? "speaker.slash" : "speaker.wave.2") { sound.toggle(); if !sound { Task { await readingServices?.speech.stopSpeaking() } } } }
                Button(photoPaused ? "继续背景轮播" : "暂停背景轮播", systemImage: "photo") { photoPaused.toggle() }
                Button("照片来源", systemImage: "info.circle") { credits = true }
                Button("暂时离开", systemImage: "pause") { dismiss() }
                if model.detail?.appointment.status == "in_progress", model.block?.ending == false {
                    Button("今天就到这里", systemImage: "leaf") { Task { await model.submit(action: .choice, finish: true) } }.disabled(!model.mayRespond)
                }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("阅读选项")
        }.foregroundStyle(paper).background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 12))
    }

    private func panel(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.beat?.speaker == "character" ? characterName(model.detail?.appointment.characterId ?? model.id) : "旁白").font(.subheadline.weight(.semibold))
                Spacer()
                Button(translation ? "中 / EN" : "EN") { translation.toggle() }.font(.caption.weight(.medium)).frame(minWidth: 52, minHeight: 44).accessibilityLabel(translation ? "隐藏中文翻译" : "显示中文翻译")
            }
            Rectangle().fill(gold.opacity(0.6)).frame(height: 1).padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let beat = model.beat {
                        if readingServices != nil {
                            TappableText(tokens: TokenCache.tokens(for: beat.english, cacheKey: "appointment-\(model.block?.id ?? "")-\(model.beatIndex)"), contextID: "appointment-\(model.id)-\(model.block?.id ?? "")-\(model.beatIndex)", textColor: ink, selection: wordSelection, onSelect: { wordSelection = $0 })
                                .font(.body).fontDesign(.rounded).accessibilityIdentifier("appointment.line")
                        } else { Text(beat.english).font(.body).textSelection(.enabled).accessibilityIdentifier("appointment.line") }
                        if translation { Text(beat.chinese).font(.subheadline).foregroundStyle(ink.opacity(0.77)).lineSpacing(5).fixedSize(horizontal: false, vertical: true) }
                    }
                    if model.isLastBeat && model.isLatestBlock && model.block?.ending == false && model.detail?.appointment.status == "in_progress" {
                        ForEach(model.block?.choices ?? []) { choice in
                            Button { Task { await model.submit(action: .choice, choiceID: choice.id) } } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Text("↗").foregroundStyle(gold)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(choice.english).font(.subheadline.weight(.medium))
                                        if translation { Text(choice.chinese).font(.caption).opacity(0.75) }
                                    }
                                    Spacer(minLength: 0)
                                }.padding(14).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                    .background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(gold.opacity(0.5), lineWidth: 1))
                            }.buttonStyle(.plain).disabled(!model.mayRespond).accessibilityIdentifier("appointment.choice.\(choice.id)")
                        }
                        Button { customInput = true } label: { Label("自己说一句，或做点别的", systemImage: "square.and.pencil").frame(maxWidth: .infinity, minHeight: 48) }
                            .buttonStyle(.plain).disabled(model.submitting || model.pending != nil).accessibilityIdentifier("appointment.custom")
                        if model.offline { Text("离线时可保存想法，联网后再发送。").font(.footnote) }
                    }
                    if model.submitting { ProgressView("你的回应已保留，正在接上下一页…").tint(ink).font(.subheadline) }
                    if let error = model.error { AppointmentErrorView(message: error, loading: model.submitting) { Task { if model.pending != nil { await model.retry() } else { await model.load() } } } }
                    else if model.pending != nil && !model.submitting { Text("上次回应已保留。"); Button("重试原回应") { Task { await model.retry() } } }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: max(44, maxHeight - 100)).fixedSize(horizontal: false, vertical: !dynamicTypeSize.isAccessibilitySize)
            .id("\(model.block?.id ?? "")-\(model.beatIndex)")
            HStack {
                Text(readingServices == nil ? "已发生的经历会保留" : "轻点英文可查词").font(.caption2).foregroundStyle(ink.opacity(0.6))
                Spacer()
                if model.isLastBeat && model.isLatestBlock && model.block?.ending == true {
                    Button("查看这次回顾") { summary = true }.font(.subheadline.weight(.semibold)).frame(minHeight: 48).accessibilityIdentifier("appointment.summary")
                } else if !model.isLastBeat || !model.isLatestBlock {
                    Button { wordSelection = nil; Task { await model.advance() } } label: { Label("继续", systemImage: "arrow.right").font(.subheadline.weight(.medium)).frame(minWidth: 72, minHeight: 44) }.accessibilityIdentifier("appointment.next")
                }
            }.padding(.top, 8)
        }
        .foregroundStyle(ink).padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 8)
        .background(paper.opacity(reduceTransparency || contrast == .increased ? 1 : 0.92), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.55), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .environment(\.colorScheme, .light)
    }

    private var inputSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("你想怎样继续？").font(.headline)
                    Text("中文、英语都可以，也可以描述想做的事。你的原话会保留；旅伴会作出自己的回应。").font(.subheadline).foregroundStyle(.secondary)
                    TextEditor(text: $model.draft).focused($inputFocused).frame(minHeight: 170).accessibilityIdentifier("appointment.input")
                    Text("\(model.draft.count) / 500").font(.caption).foregroundStyle(model.draft.count > 500 ? .red : .secondary)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    customSubmitActions += 1
                    let input = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    inputFocused = false
                    queuedCustomInput = input
                    customInput = false
                } label: {
                    Text(model.offline ? "联网后发送" : "就这样继续")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.offline || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draft.count > 500 || model.submitting || model.pending != nil)
                .accessibilityIdentifier("appointment.sendInput")
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground))
            }
            .navigationTitle("自己说一句").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("保存想法并返回") { inputFocused = false; customInput = false } } }
            .onChange(of: model.draft) { _, _ in Task { await model.persistReading() } }
            .task { inputFocused = true }
        }.environment(\.colorScheme, .light)
    }

    private func completeCustomInputDismissal() {
        inputFocused = false
        let input = queuedCustomInput
        queuedCustomInput = nil
        Task {
            await model.persistReading()
            if let input { await model.submit(action: .choice, input: input) }
        }
    }

    private var customInputDiagnostic: String {
        #if DEBUG
        "customSubmitActions:\(customSubmitActions);sheet:\(customInput);queued:\(queuedCustomInput != nil)"
        #else
        ""
        #endif
    }
}
