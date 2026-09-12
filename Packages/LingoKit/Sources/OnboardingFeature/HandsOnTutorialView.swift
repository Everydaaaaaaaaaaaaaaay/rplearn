import AVFoundation
import CoreKit
import DesignSystem
import DictKit
import DomainKit
import PersistenceKit
import SwiftUI

/// A local rehearsal: no command gateways, backend, roster or conversation stores are available here.
struct HandsOnTutorialView: View {
    let character: CharacterDTO
    let dictionary: DictDatabase
    let grammar: GrammarPointStore
    let onFinish: () async -> Bool

    private enum Step: Int { case translate, word, outing, explore }
    @State private var step: Step = .translate
    @State private var translated = false
    @State private var lookedUp = false
    @State private var selection: TokenSelection?
    @State private var encountered = false
    @State private var reply: String?
    @State private var addedPracticeFriend = false
    @State private var resolvedEncounter = false
    @State private var saving = false
    @State private var failed = false
    @State private var speaker = AVSpeechSynthesizer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sentence = "That sounds lovely. Tell me more!"
    private var name: String { character.card.name.components(separatedBy: " ").first ?? character.card.name }
    private var ready: Bool {
        switch step {
        case .translate: translated
        case .word: lookedUp
        case .outing: resolvedEncounter
        case .explore: true
        }
    }
    private var guideIsGaga: Bool {
        step == .word || (step == .outing && encountered && !resolvedEncounter)
    }
    private var guidance: String {
        switch step {
        case .translate:
            translated ? "看懂啦！同一个菜单里也能播放语音，想听就试试，咕。" : "看不懂整句时，长按下面的气泡，再点「翻译」试试，咕。"
        case .word:
            lookedUp ? "不用背下来，聊到哪儿查到哪儿就行，嘎。" : "只是不认识一个词？点一下 lovely，释义就在旁边，嘎。"
        case .outing:
            !encountered ? "去公园转一圈吧，咕。这次是练习，马上就能看到相遇的故事。"
                : !resolvedEncounter ? "选一句你想说的话就行，嘎。故事结束后，加不加好友都由你。"
                : "这次相遇只留在练习里，咕。正式外出时，你也可以自由选择。"
        case .explore:
            "机票能带你去别的城市，剧情里也藏着新的故事，咕。剩下的惊喜，自己去翻翻吧，咕！"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("上手试一试").font(.headline)
                Spacer()
                Button("跳过教程", action: finish)
                    .disabled(saving)
                    .accessibilityIdentifier("tutorial.skip")
            }.padding()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .top, spacing: 12) {
                            BrandMascotView(pose: guideIsGaga ? .reminder : .guide, size: 48, showsShadow: false)
                            Text(guidance).font(.body).lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if step == .translate || step == .word {
                            chat
                        } else if step == .outing {
                            outing
                        } else {
                            VStack(alignment: .leading, spacing: 18) {
                                Label("聊天 · 随时点词，长按气泡", systemImage: "bubble.left.and.bubble.right")
                                Label("活动 · 选个去处，遇见新故事", systemImage: "figure.walk")
                                Label("地图与剧情 · 留给你好奇心", systemImage: "globe")
                            }.font(.headline)
                        }
                        Text("练习不保存聊天或好友，也不消耗金币和积分。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Color.clear.frame(height: 1).id("tutorial.bottom")
                    }.padding(20)
                }
                .onChange(of: reply) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo("tutorial.bottom", anchor: .bottom)
                    }
                }
            }
            HStack {
                if step != .explore {
                    Button("跳过这一步") { advance() }
                        .accessibilityIdentifier("tutorial.skipStep")
                    Spacer()
                }
                Button(action: { step == .explore ? finish() : advance() }) {
                    if saving { ProgressView() }
                    else { Text(step == .explore ? "开始我的旅程" : "继续").bold() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ready || saving)
                .accessibilityIdentifier("tutorial.next")
            }.padding()
        }
        .background(Color.dsBackground)
        .wordLookupOverlay(selection: $selection, dictionary: dictionary, grammar: grammar,
            onSpeak: speak,
            exampleTranslationActions: .init(translate: { _ in nil }),
            allowsSystemTranslationFallback: false)
        .alert("暂时无法出发", isPresented: $failed) {
            Button("再试一次", action: finish)
            Button("稍后再试", role: .cancel) {}
        } message: { Text("旅伴选择还没有保存成功，练习内容不会写入账号。") }
        .onDisappear { speaker.stopSpeaking(at: .immediate) }

    }

    private var chat: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                AvatarBadge(name: character.card.name, size: 36, imageName: character.card.avatarAssetName)
                Text(name).font(.headline)
                Text("练习对话").font(.caption).foregroundStyle(.secondary)
            }
            MessageBubble(side: .incoming, contextMenu: {
                Button { translated = true } label: { Label("翻译", systemImage: "character.book.closed.zh") }
                Button { speak(sentence) } label: { Label("播放", systemImage: "speaker.wave.2") }
            }) {
                VStack(alignment: .leading, spacing: 10) {
                    TappableText(tokens: TokenCache.tokens(for: sentence, cacheKey: "tutorial-chat"),
                        contextID: "tutorial-chat", selection: selection,
                        onSelect: { selected in selection = selected; lookedUp = true })
                    if translated {
                        Text("听起来很棒，再跟我说说！")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("tutorial.translation")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tutorial.bubble")
        }
    }

    private var outing: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("公园 · 午后长椅", systemImage: "tree").font(.title3.bold())
            if !encountered {
                Text("一小段空闲，去看看今天会遇到谁。").foregroundStyle(.secondary)
                Button("去公园走走") { encountered = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("tutorial.outing")
            } else {
                Text("练习角色 · Alex").font(.headline)
                Text("一阵风吹散了长椅上的明信片。你帮忙捡起一张，上面画着一只歪歪扭扭的猫。")
                    .lineSpacing(4)
                MessageBubble(side: .incoming) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Thanks! That's my cat. I'm still learning to draw.")
                        Text("谢谢！这是我的猫，我还在学画画。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if let reply {
                    MessageBubble(side: .outgoing) { Text(reply).foregroundStyle(.white) }
                    Text(reply == "Your cat has character!" ? "Alex 笑出了声，把这张画收进了本子，决定留着它。" : "Alex 翻到第一页，让你看那只曾经被画得像土豆的猫。")
                        .foregroundStyle(.secondary)
                    MessageBubble(side: .incoming) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Maybe I'll show you my next drawing here sometime.")
                            Text("或许下次可以在这里给你看我的新画。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if resolvedEncounter {
                        Label(addedPracticeFriend ? "已体验添加好友" : "已体验结束相遇", systemImage: "checkmark.circle")
                            .foregroundStyle(Color.dsSuccess)
                    } else {
                        HStack {
                            Button("加为好友") { addedPracticeFriend = true; resolvedEncounter = true }
                                .buttonStyle(.borderedProminent).accessibilityIdentifier("tutorial.addFriend")
                            Button("道别离开") { resolvedEncounter = true }
                                .buttonStyle(.bordered)
                        }
                    }
                } else {
                    ForEach(["Your cat has character!", "How long have you been drawing?"], id: \.self) { choice in
                        Button { reply = choice } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(choice)
                                Text(choice == "Your cat has character!" ? "你的猫很有个性！" : "你学画画多久了？")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier(choice == "Your cat has character!" ? "tutorial.choice.a" : "tutorial.choice.b")
                    }
                }
            }
        }
    }

    private func speak(_ text: String) {
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        speaker.speak(utterance)
    }

    private func advance() {
        selection = nil
        speaker.stopSpeaking(at: .immediate)
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    private func finish() {
        guard !saving else { return }
        selection = nil
        speaker.stopSpeaking(at: .immediate)
        saving = true
        Task {
            if !(await onFinish()) { failed = true }
            saving = false
        }
    }
}
