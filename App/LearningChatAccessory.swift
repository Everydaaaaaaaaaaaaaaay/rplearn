import DomainKit
import PersistenceKit
import SwiftUI

/// An app-assembled accessory: ChatFeature owns conversation/layout, not learning storage.
struct LearningChatAccessory: View {
    let character: CharacterDTO
    let environment: AppEnvironment
    let busy: Bool
    let composing: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var model: ConversationLearningSystem?
    @State private var expanded = false
    @State private var showsDetails = false

    var body: some View {
        Group {
            if let model, model.ready {
                VStack(spacing: 0) {
                    header(model)
                    if expanded {
                        ScrollView {
                            card(model)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.bottom, 12)
                        }
                        .accessibilityIdentifier("chat.learning.card")
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(maxHeight: 210)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                    }
                }
                .background {
                    if reduceTransparency { Color(.secondarySystemBackground) }
                    else { Rectangle().fill(.regularMaterial) }
                }
                .overlay(alignment: .bottom) { Divider().opacity(0.35) }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: expanded)
                .onChange(of: model.state.ledger.evidence.count) { offerIfAppropriate(model) }
                .onChange(of: model.state.receipts?[character.id]?.id) { offerIfAppropriate(model) }
                .onChange(of: busy) { if !busy { offerIfAppropriate(model) } }
                .onChange(of: composing) {
                    if composing { expanded = false }
                    else { offerIfAppropriate(model) }
                }
                .onChange(of: model.state.challenge?.task.id) {
                    if model.state.challenge == nil { offerIfAppropriate(model) }
                }
            } else if let model, let error = model.error {
                Button { showsDetails = true } label: {
                    Label("学习记录暂不可用", systemImage: "exclamationmark.circle")
                        .font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                }.accessibilityHint(error)
            } else {
                // Keep a mounted host while loading. An empty Group never starts
                // its .task, leaving the production accessory permanently absent.
                Color.clear.frame(height: 1).accessibilityHidden(true)
            }
        }
        .task(id: character.id) {
            model = environment.learningSystem()
            await model?.load()
            if let model { model.resume(environment: environment); offerIfAppropriate(model) }
        }
        .sheet(isPresented: $showsDetails) {
            NavigationStack {
                ConversationLearningDashboard(character: character, environment: environment)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showsDetails = false } } }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .learningChallengeDidBegin)) { notification in
            guard notification.object as? UUID == character.id else { return }
            showsDetails = false
            expanded = true
        }
    }

    private func header(_ model: ConversationLearningSystem) -> some View {
        HStack(spacing: 8) {
            Button {
                expanded.toggle()
                if !expanded {
                    model.acknowledge(model.unreadEvidence(characterID: character.id))
                    model.acknowledgeReceipt(characterID: character.id)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "leaf.fill").font(.system(size: 16)).foregroundStyle(.teal)
                    Text(title(model)).font(.subheadline.weight(.medium)).lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    Spacer(minLength: 4)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold))
                }.contentShape(Rectangle()).frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.learning.expand")
            .accessibilityLabel("学习：\(title(model))")
            .accessibilityValue(expanded ? "已展开" : "已收起")
            Button { showsDetails = true } label: {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 18)).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("学习记录与听力")
                .accessibilityIdentifier("chat.learning.details")
        }.padding(.leading, 16).padding(.trailing, 4)
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
    }

    private func title(_ model: ConversationLearningSystem) -> String {
        if !model.state.enabled { return model.presentation.hasChosenRecording ? "学习记录已暂停" : "让每次聊天留下进步" }
        if let task = model.state.challenge, task.characterID == character.id { return "正在练习 · \(task.task.skill.title)" }
        if model.error != nil { return "学习回顾待处理 · 聊天不受影响" }
        if let evidence = model.unreadEvidence(characterID: character.id) { return "新收获 · \(evidence.skill.title)" }
        if model.unreadReceipt(characterID: character.id) != nil { return "本次回顾完成 · 查看结果" }
        if model.reviewLimitReached { return "今日学习回顾已达上限 · 聊天不受影响" }
        if model.state.ledger.nextReview(now: .now) != nil { return "有个表达，换个情境试试" }
        return model.reviewing ? "正在整理这次聊天的收获" : "聊天中学习 · Lv.\(model.state.ledger.level)"
    }

    @ViewBuilder private func card(_ model: ConversationLearningSystem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.state.enabled {
                Text("照常聊天，我们帮你发现已经会用的表达。")
                    .font(.subheadline.weight(.semibold))
                Text("只回顾开启后的新消息。每日至多 6 批成功回顾、12 次请求；后台回顾不扣可用积分，随时可暂停。参与经验不等于英语等级。")
                    .font(.footnote).foregroundStyle(.secondary)
                actionLayout {
                    Button("开启聊天学习") { model.setEnabled(true); model.resume(environment: environment); expanded = false }
                        .buttonStyle(.borderedProminent).tint(.teal).accessibilityIdentifier("chat.learning.enable")
                    Button("暂时不用") { model.setEnabled(false); expanded = false }.buttonStyle(.borderless)
                }
            } else if let task = model.state.challenge {
                if task.characterID == character.id {
                    Text(task.task.instruction).font(.subheadline.weight(.semibold))
                    Text("直接在下面聊天，分几句话说也可以。你停下来且朋友回复后会整理结果；查词或翻译会记作辅助练习。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if model.reviewing { Label("正在回顾，不用重复作答", systemImage: "clock").font(.footnote) }
                    actionLayout {
                        Button("知道了") { expanded = false }.buttonStyle(.bordered)
                        Button("结束这次练习") { model.endChallenge(); expanded = false }.buttonStyle(.borderless)
                    }
                } else {
                    Text("你在另一个聊天里还有一次练习。这里仍可照常聊天和记录收获。")
                        .font(.subheadline)
                    Button("结束之前的练习") { model.endChallenge() }.buttonStyle(.bordered)
                }
            } else {
                if let evidence = model.unreadEvidence(characterID: character.id) {
                    Label(evidence.successful ? "这次你做到了" : "这次表达的发现", systemImage: evidence.successful ? "checkmark.circle" : "lightbulb")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.teal)
                    Text(evidence.explanation).font(.subheadline)
                    Text(evidence.independent ? "已留下独立表达证据；一次表现不代表等级提升。" : "已记录为辅助练习，不用于确认独立英语能力。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if let receipt = model.state.receipts?[character.id] {
                    Text(receipt.summary).font(.subheadline)
                } else if model.state.ledger.nextReview(now: .now) != nil {
                    Text("上次练过的表达，今天换个情境再用一次。")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("照常聊，就是在练习。也可以自选一个小情境。")
                        .font(.subheadline.weight(.semibold))
                    Text("表达选择、描述经历、安排计划、澄清误解。我们看你能否把意思说清楚，不按聊天时长判定升级。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if model.reviewLimitReached {
                    Text("今日已完成回顾或用满请求上限。新表达会保留到之后处理，不影响聊天，也不会扣分。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.error {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("重试回顾") { Task { await model.review(environment: environment, force: true) } }
                        .disabled(model.reviewing || busy || model.reviewLimitReached).accessibilityIdentifier("chat.learning.retry")
                }
                actionLayout {
                    Button("试个小情境") {
                        model.acknowledge(model.unreadEvidence(characterID: character.id))
                        model.acknowledgeReceipt(characterID: character.id)
                        model.startRecommendedChallenge(characterID: character.id)
                    }.buttonStyle(.borderedProminent).tint(.teal)
                        .disabled(busy || model.reviewing || model.reviewLimitReached)
                        .accessibilityIdentifier("chat.learning.practice")
                    Button("今天先不练") {
                        model.acknowledge(model.unreadEvidence(characterID: character.id))
                        model.acknowledgeReceipt(characterID: character.id)
                        model.deferLearning(); expanded = false
                    }.buttonStyle(.borderless)
                }
                Button("暂停学习记录") { model.setEnabled(false); expanded = false }
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func offerIfAppropriate(_ model: ConversationLearningSystem) {
        guard model.state.enabled, model.state.challenge == nil, !expanded,
              model.presentation.canInvite(now: .now, busy: busy, composing: composing),
              model.unreadEvidence(characterID: character.id) != nil || model.unreadReceipt(characterID: character.id) != nil || (!model.reviewLimitReached && model.state.ledger.nextReview(now: .now) != nil) else { return }
        model.presentation.markInvitation(now: .now)
        model.persist()
        expanded = true
    }
}
