import BackendKit
import CoreKit
import DesignSystem
import DictKit
import DomainKit
import PersistenceKit
import SpeechKit
import SwiftUI

struct CityOutingView: View {
    @ObservedObject var model: CityOutingModel
    let isVisible: Bool
    let onBack: () -> Void
    let onChat: (CharacterDTO) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var translation = false
    @State private var autoRead = true
    @State private var word: TokenSelection?
    @State private var credits: BackendActivityPhoto?
    @State private var confirmsEnding = false
    private let ink = DSReadingPalette.ink

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                GeometryReader { scene in
                    ActivityPlacePhoto(photo: model.snapshot?.photo ?? model.archive.place.photo)
                        .frame(width: scene.size.width, height: scene.size.height).clipped()
                        .overlay {
                            LinearGradient(colors: [.black.opacity(0.48), .clear, .black.opacity(0.12)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                }.ignoresSafeArea()
                VStack(spacing: 0) {
                    toolbar
                    HStack {
                        Button { credits = model.snapshot?.photo ?? model.archive.place.photo } label: {
                            Label("地点照片", systemImage: "info.circle").font(.caption).frame(minHeight: 44)
                        }.accessibilityLabel("照片信息")
                        Spacer()
                    }.foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 28)
                    Spacer(minLength: 12)
                    ScrollViewReader { reader in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                if let snapshot = model.snapshot { story(snapshot) }
                                else { ProgressView("正在走进\(model.archive.place.titleZh)…").frame(maxWidth: .infinity).padding(.vertical, 30) }
                                if let message = model.synchronizationMessage {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(message).font(.caption)
                                        if model.conflict { Button("恢复服务器进度") { model.restoreServerProgress() } }
                                        else { Button("重试同步") { model.retrySynchronization() } }
                                    }.font(.subheadline).foregroundStyle(DSReadingPalette.secondary)
                                }
                                if let error = model.error {
                                    Text(error).font(.callout)
                                    Button("重试，保留当前人物与选择") { model.retry() }
                                }
                                Color.clear.frame(height: 1).id("outing-bottom")
                            }.padding(18)
                        }.scrollBounceBehavior(.basedOnSize)
                            .frame(maxHeight: geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.83 : 0.64))
                            .background(DSReadingPalette.paper.opacity(reduceTransparency || contrast == .increased ? 1 : 0.95), in: RoundedRectangle(cornerRadius: 12))
                            .onChange(of: model.snapshot?.revision) { _, _ in
                                model.confirmVisibleOpening(); model.updateAutoReading(enabled: shouldRead)
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { reader.scrollTo("outing-bottom", anchor: .bottom) }
                            }
                    }.frame(maxWidth: 620).padding(.horizontal, 18).padding(.bottom, 14)
                }
            }
        }
        .foregroundStyle(ink).tint(DSReadingPalette.tint)
        .background(DSReadingPalette.canvas)
        .dsTabBarHidden()
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["UI_TEST_OUTING_AUDIO"] == "0" { autoRead = false }
            #endif
            model.start(); model.confirmVisibleOpening()
        }
        .onDisappear { model.updateAutoReading(enabled: false) }
        .onChange(of: shouldRead) { _, enabled in model.updateAutoReading(enabled: enabled) }
        .sheet(item: $credits) { ActivityPhotoCredits(photo: $0) }
        .confirmationDialog("结束这次外出？已发生的进度仍会保留。", isPresented: $confirmsEnding, titleVisibility: .visible) {
            Button("结束这次外出", role: .destructive) { model.abandon(); onBack() }
            Button("继续这次外出", role: .cancel) {}
        }
        .wordLookupOverlay(selection: $word, dictionary: model.deps.dictionary, grammar: model.deps.grammarPoints,
            onSpeak: { value in
                let stopped = model.stopSpeech()
                Task { await stopped?.value; await model.deps.speech.speak(.init(text: value, purpose: .pronunciation)) }
            }, favoriteActions: WordFavoriteActions(
                contains: { (try? await model.deps.favorites.isWordFavorited($0)) ?? false },
                toggle: { (try? await model.deps.favorites.toggleWord($0, translationZh: $1)) ?? false }))
    }
    private var shouldRead: Bool { autoRead && isVisible && scenePhase == .active }
    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
            Button(action: onBack) { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("暂停并返回地点").accessibilityIdentifier("activities.action.back")
            if !dynamicTypeSize.isAccessibilitySize { placeHeading }
            Spacer(minLength: 0)
            Button { translation.toggle() } label: { Image(systemName: "character.bubble").frame(width: 44, height: 44) }
                .accessibilityLabel(translation ? "隐藏中文对照" : "显示中文对照")
            Button { autoRead.toggle() } label: { Image(systemName: autoRead ? "speaker.wave.2" : "speaker.slash").frame(width: 44, height: 44) }
                .accessibilityLabel(autoRead ? "关闭自动朗读" : "开启自动朗读")
            Menu {
                Button("先离开，稍后继续", action: onBack)
                Button("结束这次外出", role: .destructive) { confirmsEnding = true }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("外出选项")
        }.font(.system(size: 18, weight: .medium))
        if dynamicTypeSize.isAccessibilitySize { placeHeading.padding(.horizontal, 8) }
        }.padding(.leading, 28).padding(.trailing, 8).padding(.vertical, 6).foregroundStyle(.white)
    }
    private var placeHeading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.region.nameZh).font(.caption).foregroundStyle(.white.opacity(0.75))
            Text(model.archive.place.titleZh).font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func story(_ snapshot: BackendOuting) -> some View {
        if let npc = snapshot.npc {
            HStack(spacing: 12) {
                AvatarBadge(name: npc.card.name, size: 44, remoteURL: npc.avatar?.url, usesPendingPlaceholder: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.character?.displayName ?? npc.card.name).font(.headline)
                    Text(npc.card.occupation).font(.caption).foregroundStyle(ink.opacity(0.6))
                }
            }
        }
        Text(snapshot.mode == .solitude ? snapshot.solitude.titleZh
             : snapshot.mode == .reunion ? snapshot.story?.reunion.titleZh ?? "又见面了" : snapshot.story?.titleZh ?? "一次相遇")
            .font(.system(.title, design: .serif, weight: .medium))
        if snapshot.mode == .solitude {
            lookup(snapshot.solitude.english, key: "quiet")
            if translation { Text(snapshot.solitude.chinese).foregroundStyle(ink.opacity(0.65)) }
        } else {
            ForEach(Array(model.chapters.enumerated()), id: \.offset) { stage, chapter in
                ForEach(Array(chapter.beats.enumerated()), id: \.offset) { index, beat in
                    if stage < model.chapters.count - 1 || index <= snapshot.beatIndex {
                        VStack(alignment: .leading, spacing: 8) {
                            lookup(beat.english, key: "\(stage):\(index)")
                            if translation { Text(beat.chinese).font(.subheadline).foregroundStyle(ink.opacity(0.65)) }
                        }.lineSpacing(6)
                            .foregroundStyle(beat.speaker == "narrator" ? ink.opacity(0.72) : ink)
                            .padding(.leading, beat.speaker == "narrator" ? 12 : 0)
                            .accessibilityIdentifier("activities.placeBeat.\(stage).\(index)")
                    }
                }
                if snapshot.choices.indices.contains(stage),
                   let index = Int(snapshot.choices[stage].split(separator: ":").last ?? ""), chapter.choices.indices.contains(index) {
                    Label(chapter.choices[index].english, systemImage: "arrow.turn.down.right")
                        .font(.subheadline).foregroundStyle(ink.opacity(0.6))
                }
            }
        }
        if snapshot.status == .completed || snapshot.status == .abandoned { ending(snapshot) }
        else if !model.choices.isEmpty {
            ForEach(Array(model.choices.enumerated()), id: \.offset) { index, choice in
                DSReadingChoice(english: choice.english, chinese: translation ? choice.chinese : nil) {
                    model.choose(index)
                }.disabled(model.conflict)
                    .accessibilityIdentifier("activities.choice.\(index)")
            }
        } else {
            Button { model.advance() } label: {
                Text(model.isAtEnding ? "结束这次外出" : "继续")
            }
                .buttonStyle(.dsActionPrimary)
                .disabled(model.conflict || (snapshot.status == .reserved && snapshot.beatIndex == model.currentBeats.count - 1))
                .accessibilityIdentifier("activities.action.next")
        }
    }
    private func lookup(_ text: String, key: String) -> some View {
        let context = "place-outing:\(model.archive.runID):\(key)"
        return TappableText(tokens: TokenCache.tokens(for: text, cacheKey: context), contextID: context,
            textColor: ink, selection: word, lookupOnLongPress: false, onSelect: { word = $0 })
            .fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private func ending(_ snapshot: BackendOuting) -> some View {
        if snapshot.mode != .solitude && snapshot.status == .completed {
            if let character = model.character, character.isFriend {
                Button { onChat(character) } label: { Text("继续聊天") }
                    .buttonStyle(.dsActionPrimary)
            } else {
                Button { model.addFriend() } label: {
                    Text(model.pendingCount > 0 ? "同步完成后可添加好友" : "加为好友")
                }
                    .buttonStyle(.dsActionPrimary)
                    .disabled(model.pendingCount > 0 || model.contactBusy)
                    .accessibilityIdentifier("activities.encounter.addFriend")
            }
        }
        if let message = model.contactMessage { Text(message).font(.caption) }
        Button("回到城市地点", action: onBack).frame(minHeight: 44).accessibilityIdentifier("activities.action.finish")
    }
}
