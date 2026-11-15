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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var translation = false
    @State private var autoRead = true
    @State private var word: TokenSelection?
    @State private var credits: BackendActivityPhoto?
    @State private var confirmsEnding = false
    private let ink = Color.dsTravelNavy

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 270)
                        .overlay(alignment: .bottomTrailing) {
                            Button { credits = model.snapshot?.photo ?? model.archive.place.photo } label: {
                                Image(systemName: "info.circle").frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
                            }.accessibilityLabel("照片信息").padding(10)
                        }
                    VStack(alignment: .leading, spacing: 24) {
                        if let snapshot = model.snapshot { story(snapshot) }
                        else { ProgressView("正在走进\(model.archive.place.titleZh)…").frame(maxWidth: .infinity).padding(.vertical, 30) }
                        if let message = model.synchronizationMessage {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(message).font(.caption)
                                if model.conflict { Button("恢复服务器进度") { model.restoreServerProgress() } }
                                else { Button("重试同步") { model.retrySynchronization() } }
                            }.font(.subheadline).foregroundStyle(ink.opacity(0.7))
                        }
                        if let error = model.error {
                            Text(error).font(.callout)
                            Button("重试，保留当前人物与选择") { model.retry() }
                        }
                        Color.clear.frame(height: 1).id("outing-bottom")
                    }.padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CityPlacesView.paper.opacity(0.97), in: RoundedRectangle(cornerRadius: 28))
                }.padding(.horizontal, 16).padding(.bottom, 24)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.scrollBounceBehavior(.basedOnSize)
                .onChange(of: model.snapshot?.revision) { _, _ in
                    model.confirmVisibleOpening(); model.updateAutoReading(enabled: shouldRead)
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { reader.scrollTo("outing-bottom", anchor: .bottom) }
                }
        }
        .safeAreaInset(edge: .top, spacing: 0) { toolbar }
        .foregroundStyle(ink).tint(ink)
        .background {
            ActivityPlacePhoto(photo: model.snapshot?.photo ?? model.archive.place.photo)
                .ignoresSafeArea().accessibilityHidden(true)
        }
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
        }.padding(.leading, 28).padding(.trailing, 8).padding(.vertical, 6).background(CityPlacesView.paper)
    }
    private var placeHeading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.region.nameZh).font(.caption).foregroundStyle(ink.opacity(0.6))
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
        if snapshot.mode == .solitude {
            lookup(snapshot.solitude.english, key: "quiet")
            if translation { Text(snapshot.solitude.chinese).foregroundStyle(ink.opacity(0.65)) }
        } else {
            Text(snapshot.mode == .reunion ? snapshot.story?.reunion.titleZh ?? "又见面了" : snapshot.story?.titleZh ?? "一次相遇")
                .font(.system(.title, design: .serif, weight: .medium))
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
                Button { model.choose(index) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(choice.english).font(.body.weight(.medium))
                        if translation { Text(choice.chinese).font(.subheadline) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(DSSceneEntranceButtonStyle()).disabled(model.conflict)
                    .accessibilityIdentifier("activities.choice.\(index)")
            }
        } else {
            Button { model.advance() } label: {
                Text(model.isAtEnding ? "结束这次外出" : "继续").foregroundStyle(.white)
            }
                .buttonStyle(.borderedProminent).controlSize(.large)
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
                Button { onChat(character) } label: { Text("继续聊天").foregroundStyle(.white) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Button { model.addFriend() } label: {
                    Text(model.pendingCount > 0 ? "同步完成后可添加好友" : "加为好友").foregroundStyle(.white)
                }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.pendingCount > 0 || model.contactBusy)
                    .accessibilityIdentifier("activities.encounter.addFriend")
            }
        }
        if let message = model.contactMessage { Text(message).font(.caption) }
        Button("回到城市地点", action: onBack).frame(minHeight: 44).accessibilityIdentifier("activities.action.finish")
    }
}
