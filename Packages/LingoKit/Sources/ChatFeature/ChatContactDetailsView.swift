import DesignSystem
import Foundation
import Observation
import PersistenceKit
import SwiftUI

/// 从聊天页进入的联系人设置。它只管理当前用户的私有关系状态，不修改公共 NPC 身份。
struct ChatContactDetailsView: View {
    @Bindable var viewModel: ChatViewModel
    let onSelectMessage: (UUID) -> Void
    let onRemoved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPinned: Bool
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showsClearConfirmation = false
    @State private var showsRemoveConfirmation = false

    init(
        viewModel: ChatViewModel,
        onSelectMessage: @escaping (UUID) -> Void,
        onRemoved: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onSelectMessage = onSelectMessage
        self.onRemoved = onRemoved
        _isPinned = State(
            initialValue: viewModel.conversation?.isPinned ?? false
        )
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    ChatCharacterProfileView(viewModel: viewModel)
                } label: {
                    profileRow
                }

                NavigationLink {
                    ChatHistorySearchView(
                        viewModel: viewModel,
                        onSelect: { messageID in
                            onSelectMessage(messageID)
                            dismiss()
                        }
                    )
                } label: {
                    Label("查找聊天记录", systemImage: "magnifyingglass")
                }
            }

            if let attribution = viewModel.character.card.avatarAttribution, !attribution.isEmpty {
                Section("头像来源") {
                    Text(attribution)
                    if let source = viewModel.character.card.avatarSourceURL,
                       let url = URL(string: source), url.scheme == "https" {
                        Link("查看来源与授权", destination: url)
                    }
                }
            }

            Section("聊天设置") {
                Toggle("特别关心", systemImage: "star.fill", isOn: favoriteBinding)
                Toggle("置顶聊天", systemImage: "pin.fill", isOn: pinnedBinding)

                Menu {
                    Button("关闭免打扰") { setMutedUntil(nil) }
                    Button("1 小时") { setMutedUntil(.now.addingTimeInterval(3_600)) }
                    Button("8 小时") { setMutedUntil(.now.addingTimeInterval(28_800)) }
                    Button("1 天") { setMutedUntil(.now.addingTimeInterval(86_400)) }
                    Button("1 周") { setMutedUntil(.now.addingTimeInterval(604_800)) }
                } label: {
                    LabeledContent {
                        Text(muteStatus)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("消息免打扰", systemImage: "bell.slash.fill")
                            .foregroundStyle(.primary)
                    }
                }

                Toggle(
                    "允许主动问候",
                    systemImage: "bubble.left.and.exclamationmark.bubble.right.fill",
                    isOn: proactiveBinding
                )
            }

            Section {
                NavigationLink {
                    ContactNoteEditor(viewModel: viewModel)
                } label: {
                    LabeledContent("备注与私人笔记") {
                        Text(noteSummary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                NavigationLink {
                    CharacterGrowthManagementView(viewModel: viewModel)
                } label: {
                    LabeledContent {
                        Text(growthSummary)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("成长与记忆", systemImage: "leaf.fill")
                    }
                }
            } header: {
                Text("只对你可见")
            } footer: {
                Text("备注与关系成长只属于你和这位旅伴；你可以随时查看、暂停或撤销成长。")
            }

            Section {
                Button("清空聊天记录", role: .destructive) {
                    showsClearConfirmation = true
                }
                .disabled(isWorking || viewModel.messages.isEmpty)

                Button("移除好友", role: .destructive) {
                    showsRemoveConfirmation = true
                }
                .disabled(isWorking || !viewModel.character.isFriend)
            } footer: {
                Text("移除后会保留聊天和共同经历，可在“过往联系人”中重新添加。")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.dsDanger)
                }
            }
        }
        .navigationTitle("聊天设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
        .disabled(isWorking)
        .overlay {
            if isWorking { ProgressView().controlSize(.large) }
        }
        .task { await viewModel.refreshCharacter() }
        .confirmationDialog(
            "清空与\(viewModel.character.displayName)的聊天记录？",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空聊天记录", role: .destructive) { clearHistory() }
        } message: {
            Text("聊天消息和聊天中提炼的记忆会被删除；剧情经历、好友关系和已形成的成长不会受影响。此操作无法撤销。")
        }
        .confirmationDialog(
            "移除\(viewModel.character.displayName)？",
            isPresented: $showsRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("移除好友", role: .destructive) { removeFriend() }
        } message: {
            Text("不会删除聊天和共同经历。主线剧情也不会在之后自动把这位旅伴加回来。")
        }
    }

    private var profileRow: some View {
        HStack(spacing: DSSpacing.sm) {
            AvatarBadge(
                name: viewModel.character.displayName,
                size: 58,
                imageName: viewModel.character.card.avatarAssetName,
                remoteURL: viewModel.character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                attribution: viewModel.character.card.avatarAttribution,
                sourceURL: viewModel.character.card.avatarSourceURL.flatMap(URL.init(string:))
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.character.displayName)
                    .font(.headline)
                Text(viewModel.character.card.signature ?? "查看旅伴资料与成长故事")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var favoriteBinding: Binding<Bool> {
        Binding(
            get: { viewModel.character.isFavorite },
            set: { newValue in
                performUpdate {
                    try await viewModel.setFavorite(newValue)
                }
            }
        )
    }

    private var pinnedBinding: Binding<Bool> {
        Binding(
            get: { isPinned },
            set: { newValue in
                guard viewModel.conversation != nil, isPinned != newValue else { return }
                isPinned = newValue
                performUpdate {
                    try await viewModel.setPinned(newValue)
                }
            }
        )
    }

    private var proactiveBinding: Binding<Bool> {
        Binding(
            get: { viewModel.character.contactPreferences.proactiveMessagesEnabled },
            set: { newValue in
                var preferences = viewModel.character.contactPreferences
                preferences.proactiveMessagesEnabled = newValue
                performUpdate {
                    try await viewModel.updateContactPreferences(preferences)
                }
            }
        )
    }

    private var muteStatus: String {
        guard let until = viewModel.character.contactPreferences.mutedUntil,
              until > .now
        else { return "未开启" }
        return "至 " + until.formatted(date: .abbreviated, time: .shortened)
    }

    private var noteSummary: String {
        if let remark = viewModel.character.contactPreferences.remarkName, !remark.isEmpty {
            return remark
        }
        if let note = viewModel.character.contactPreferences.privateNote, !note.isEmpty {
            return note
        }
        return "未设置"
    }

    private var growthSummary: String {
        if viewModel.character.growth.isPaused { return "已暂停" }
        let count = viewModel.character.growth.arcs.count
        return count == 0 ? "尚未形成" : "\(count) 项"
    }

    private func setMutedUntil(_ date: Date?) {
        var preferences = viewModel.character.contactPreferences
        preferences.mutedUntil = date
        performUpdate {
            try await viewModel.updateContactPreferences(preferences)
        }
    }

    private func performUpdate(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await operation()
                Haptics.selection()
            } catch {
                errorMessage = "设置没有保存成功，请重试。"
            }
            isWorking = false
        }
    }

    private func clearHistory() {
        performUpdate {
            try await viewModel.clearHistory()
        }
    }

    private func removeFriend() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await viewModel.removeFriend()
                Haptics.notify(.success)
                onRemoved()
            } catch {
                errorMessage = "好友没有移除成功，请重试。"
                isWorking = false
            }
        }
    }
}

private struct ContactNoteEditor: View {
    @Bindable var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var remarkName: String
    @State private var privateNote: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
        _remarkName = State(initialValue: viewModel.character.contactPreferences.remarkName ?? "")
        _privateNote = State(initialValue: viewModel.character.contactPreferences.privateNote ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField(viewModel.character.card.name, text: $remarkName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("备注名")
            } footer: {
                Text("最多 40 个字符；只在你的联系人和聊天中显示。")
            }

            Section {
                TextEditor(text: $privateNote)
                    .frame(minHeight: 150)
            } header: {
                Text("私人笔记")
            } footer: {
                Text("最多保存 500 个字符，NPC 不会看到这段内容。")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.dsDanger)
                }
            }
        }
        .navigationTitle("备注与笔记")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(isSaving)
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        var preferences = viewModel.character.contactPreferences
        preferences.remarkName = String(remarkName.prefix(40))
        preferences.privateNote = String(privateNote.prefix(500))
        Task {
            do {
                try await viewModel.updateContactPreferences(preferences)
                dismiss()
            } catch {
                errorMessage = "备注没有保存成功，请重试。"
                isSaving = false
            }
        }
    }
}

private struct ChatHistorySearchView: View {
    @Bindable var viewModel: ChatViewModel
    let onSelect: (UUID) -> Void
    @State private var query = ""
    @State private var results: [ChatMessageSearchResultDTO] = []
    @State private var isSearching = false
    @State private var didSearch = false
    @State private var searchFailed = false

    private var characterName: String { viewModel.character.displayName }

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "查找聊天记录",
                    systemImage: "text.magnifyingglass",
                    description: Text("搜索你与\(characterName)说过的单词或句子")
                )
            } else if isSearching {
                ProgressView("正在搜索…")
            } else if searchFailed {
                ContentUnavailableView(
                    "搜索暂时不可用",
                    systemImage: "exclamationmark.magnifyingglass",
                    description: Text("请稍后重试")
                )
            } else if didSearch, results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results) { result in
                    if result.conversationID == viewModel.conversation?.id {
                        Button { onSelect(result.message.id) } label: {
                            resultLabel(result)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            ChatHistoryContextView(viewModel: viewModel, result: result)
                        } label: {
                            resultLabel(result)
                        }
                    }
                }
            }
        }
        .navigationTitle("聊天记录")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索聊天内容")
        .task(id: query) { await search() }
    }

    private func resultLabel(_ result: ChatMessageSearchResultDTO) -> some View {
        let message = result.message
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(message.role == .user ? "我" : characterName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dsSkyDeep)
                if result.isArchivedConversation {
                    Text("历史会话")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(message.text)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
        }
        .padding(.vertical, 3)
    }

    @MainActor
    private func search() async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            results = []
            isSearching = false
            didSearch = false
            searchFailed = false
            return
        }
        isSearching = true
        didSearch = false
        searchFailed = false
        do {
            try await Task.sleep(for: .milliseconds(180))
            let matches = try await viewModel.searchHistory(normalized)
            guard !Task.isCancelled else { return }
            results = matches
            didSearch = true
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            didSearch = true
            searchFailed = true
        }
        isSearching = false
    }
}

private struct ChatHistoryContextView: View {
    let viewModel: ChatViewModel
    let result: ChatMessageSearchResultDTO
    @State private var messages: [MessageDTO] = []
    @State private var isLoading = true

    var body: some View {
        ScrollViewReader { proxy in
            List(messages) { message in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(message.role == .user ? "我" : viewModel.character.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.dsSkyDeep)
                        Spacer()
                        Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
                .listRowBackground(
                    message.id == result.message.id ? Color.dsSky.opacity(0.14) : Color.clear
                )
                .id(message.id)
            }
            .overlay {
                if isLoading { ProgressView() }
            }
            .task {
                messages = (try? await viewModel.historyMessages(
                    conversationID: result.conversationID
                )) ?? []
                isLoading = false
                await Task.yield()
                proxy.scrollTo(result.message.id, anchor: .center)
            }
        }
        .navigationTitle(result.isArchivedConversation ? "历史会话" : "聊天上下文")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChatCharacterProfileView: View {
    @Bindable var viewModel: ChatViewModel

    private var character: CharacterDTO { viewModel.character }

    var body: some View {
        List {
            Section {
                VStack(spacing: DSSpacing.sm) {
                    AvatarBadge(
                        name: character.displayName,
                        size: 96,
                        imageName: character.card.avatarAssetName,
                        remoteURL: character.card.avatarRemoteURL.flatMap(URL.init(string:)),
                        attribution: character.card.avatarAttribution,
                        sourceURL: character.card.avatarSourceURL.flatMap(URL.init(string:))
                    )
                    Text(character.displayName)
                        .font(.title2.bold())
                    if character.displayName != character.card.name {
                        Text(character.card.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Label("AI 旅伴 · 虚构角色", systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.dsSkyDeep)
                    if let signature = character.card.signature {
                        Text(signature)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.sm)
            }

            Section("身份资料") {
                profileValue("旅伴号", value: character.travelerID)
                profileValue("职业", value: character.card.occupation)
                profileValue("性别", value: genderName)
                profileValue("年龄", value: "\(character.card.age) 岁")
                profileValue("生日", value: character.card.birthday)
                profileValue("家乡", value: character.card.hometown)
                profileValue("国籍", value: character.card.nationality)
                profileValue("语言", value: character.card.languages?.joined(separator: "、"))
            }

            Section {
                Text(character.card.personality)
                if let speechStyle = character.card.speechStyle {
                    LabeledContent("说话方式") { Text(speechStyle).multilineTextAlignment(.trailing) }
                }
                if !character.card.hobbies.isEmpty {
                    LabeledContent("爱好") {
                        Text(character.card.localizedHobbies.joined(separator: "、"))
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Text("稳定人格")
            } footer: {
                Text("这是角色长期稳定的底色；真实互动会形成缓慢的成长，但不会突然换一个人。")
            }

            if let voice = character.card.personaVoice,
               !voice.values.isEmpty || !voice.flaws.isEmpty || !voice.conversationalHabits.isEmpty {
                Section("人物内核") {
                    profileValue("看重", value: voice.values.joined(separator: "、"))
                    profileValue("不完美之处", value: voice.flaws.joined(separator: "、"))
                    profileValue("聊天习惯", value: voice.conversationalHabits.joined(separator: "、"))
                    profileValue("边界", value: voice.boundaries.joined(separator: "、"))
                }
            }

            Section {
                if character.growth.isPaused {
                    Label("未来成长已暂停", systemImage: "pause.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if character.growth.arcs.isEmpty {
                    ContentUnavailableView(
                        "还没有形成稳定变化",
                        systemImage: "leaf",
                        description: Text("一次建议只会种下想法；持续的经历与行动才会慢慢留下改变。")
                    )
                } else {
                    ForEach(character.growth.arcs.sorted { $0.updatedAt > $1.updatedAt }) { arc in
                        growthRow(arc)
                    }
                }
            } header: {
                Text("与你相处后的成长")
            } footer: {
                if character.growth.isPaused {
                    Text("已经形成的成长仍会保留；新的互动暂时不会继续改变这位旅伴。")
                }
            }

            if let background = character.card.background {
                Section("背景故事") { Text(background) }
            }

            Section("你们的关系") {
                LabeledContent("共同互动") {
                    Text("\(character.relationship.meaningfulInteractionCount) 次")
                }
                if let latest = character.relationship.latestEvent {
                    Text(latest.reasonZh)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("旅伴资料")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func profileValue(_ title: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(title) {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }

    private func growthRow(_ arc: CharacterGrowthArc) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(growthTitle(arc))
                    .font(.headline)
                Spacer()
                Text(arc.stage.titleZh)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.dsSkyDeep)
            }
            Text(arc.reasonZh)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: min(max(arc.progress, 0), 1))
                .tint(Color.dsSky)
            Text("依据 \(arc.evidenceMessageIDs.count) 条互动证据 · 更新于 \(arc.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func growthTitle(_ arc: CharacterGrowthArc) -> String {
        switch arc.direction {
        case .increase: "更有\(arc.trait.titleZh)"
        case .decrease: "减少\(arc.trait.titleZh)"
        }
    }

    private var genderName: String {
        switch character.card.gender {
        case .male: "男"
        case .female: "女"
        case .other: "未设定"
        }
    }
}
