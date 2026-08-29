#if DEBUG
import DesignSystem
import DomainKit
import LLMKit
import PersistenceKit
import SwiftUI

/// Debug 构建专用的关系算法实验室。默认只操作内存沙盒，真实写入必须二次确认。
struct RelationshipLabView: View {
    let rosterStore: RosterStore
    let llm: any LLMClient

    @State private var characters: [CharacterDTO] = []
    @State private var selectedCharacterID: UUID?
    @State private var sandbox = RelationshipSnapshot.initial
    @State private var baseline = RelationshipSnapshot.initial
    @State private var simulatedDate = Date.now
    @State private var eventSequence = 0
    @State private var source = RelationshipEventRecord.Source.textChat
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var persistenceMessage: String?
    @State private var showsPersistenceConfirmation = false
    @State private var assertions: [RelationshipLabAssertion] = []

    @State private var warmth = 0.4
    @State private var responsiveness = 0.5
    @State private var respect = 0.7
    @State private var empathy = 0.2
    @State private var reciprocity = 0.4
    @State private var disclosure = 0.1
    @State private var resonance = 0.2
    @State private var engagement = 0.5
    @State private var boundaryHarm = 0.0
    @State private var repair = 0.0
    @State private var significance = 0.3
    @State private var confidence = 0.9
    @State private var manualReason = "手动构造的测试互动"

    @State private var evaluatorContext = "I finally finished the chapter I was struggling with."
    @State private var evaluatorMessage = "That sounds brilliant — what part are you proudest of?"
    @State private var evaluatorResult: InteractionReview?
    @State private var evaluatorError: String?
    @State private var isEvaluating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedCharacter: CharacterDTO? {
        characters.first { $0.id == selectedCharacterID }
    }

    private var projectedScore: Double {
        sandbox.projectedAffinity(at: simulatedDate)
    }

    private var baselineScore: Double {
        baseline.projectedAffinity(at: simulatedDate)
    }

    private var hasFutureInteraction: Bool {
        guard let date = sandbox.lastEvaluatedMessageAt else { return false }
        return date > Date.now.addingTimeInterval(5)
    }

    private var scenarios: [RelationshipLabScenario] {
        RelationshipLabFixtures.scenarios
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在载入测试角色…")
            } else if let loadError, characters.isEmpty {
                ContentUnavailableView {
                    Label("无法载入角色", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("重试") { Task { await loadCharacters() } }
                }
            } else {
                labContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackground)
        .navigationTitle("好感度实验室")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCharacters() }
        .confirmationDialog(
            "写入真实角色关系？",
            isPresented: $showsPersistenceConfirmation,
            titleVisibility: .visible
        ) {
            Button("写入并验证", role: .destructive) {
                Task { await persistSandbox() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会覆盖所选角色当前的真实好感度。普通测试请继续使用沙盒。")
        }
    }

    private var labContent: some View {
        ScrollView {
            LazyVStack(spacing: DSSpacing.md) {
                debugNotice
                characterControls
                scoreDashboard
                quickScenarios
                evaluatorSection
                timeAndBatchSection
                manualSignalSection
                invariantSection
                eventHistorySection
                persistenceSection
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var debugNotice: some View {
        HStack(alignment: .top, spacing: DSSpacing.sm) {
            Image(systemName: "testtube.2")
                .foregroundStyle(Color.dsSky)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text("Debug 临时工具")
                    .font(.headline)
                Text("所有操作默认只进入内存沙盒，不会影响聊天中的真实关系。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .dsSurface(.grouped)
    }

    private var characterControls: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            sectionTitle("测试基线", icon: "person.crop.circle")
            Picker("角色", selection: $selectedCharacterID) {
                ForEach(characters) { character in
                    Text(character.card.name).tag(Optional(character.id))
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedCharacterID) { _, _ in
                loadSelectedRelationship()
            }

            HStack {
                Button("载入真实状态", systemImage: "arrow.clockwise") {
                    loadSelectedRelationship()
                }
                .buttonStyle(.bordered)
                Button("重置为初识", systemImage: "sparkles") {
                    resetToInitial()
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline)
        }
        .dsSurface(.grouped)
    }

    private var scoreDashboard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("当前沙盒", icon: "heart.fill")
                Spacer()
                Text("\(Int(projectedScore.rounded())) / 150")
                    .font(.title2.monospacedDigit().weight(.bold))
                    .contentTransition(.numericText())
            }
            ProgressView(value: projectedScore, total: 150)
                .tint(Color.dsSunset)
                .scaleEffect(y: 1.8)
                .padding(.vertical, DSSpacing.xxs)

            HStack(spacing: DSSpacing.sm) {
                metric("相对基线", signed(projectedScore - baselineScore), color: deltaColor(projectedScore - baselineScore))
                metric("长期下限", number(sandbox.bondFloor), color: .dsSky)
                metric("未修复张力", percent(sandbox.unresolvedStrain), color: sandbox.unresolvedStrain > 0.3 ? .dsWarning : .secondary)
            }

            Divider()
            dimension("相互了解", sandbox.familiarity)
            dimension("信任", sandbox.trust)
            dimension("默契", sandbox.rapport)
            dimension("关心互惠", sandbox.care)
            dimension("尊重", sandbox.respect)

            HStack {
                Label("\(sandbox.interactionCount) 次互动", systemImage: "bubble.left.and.bubble.right")
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("今日普通 +\(sandbox.positiveGainToday, specifier: "%.2f") / 4")
                    Text("今日修复 +\(sandbox.repairGainToday ?? 0, specifier: "%.2f") / 2")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .animation(reduceMotion ? nil : DSAnimation.snappy, value: sandbox.revision)
        .dsSurface(.elevated)
    }

    private var quickScenarios: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            sectionTitle("快速情景", icon: "square.grid.2x2")
            Text("点击即在当前模拟时间应用一次互动。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("来源", selection: $source) {
                ForEach(RelationshipEventRecord.Source.allCases, id: \.self) { value in
                    Text(value.labTitle).tag(value)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal) {
                LazyHStack(spacing: DSSpacing.sm) {
                    ForEach(scenarios) { scenario in
                        Button {
                            apply(scenario.signal)
                        } label: {
                            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                Image(systemName: scenario.icon)
                                    .font(.title2)
                                    .foregroundStyle(scenario.color)
                                Text(scenario.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(scenario.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(width: 150, alignment: .leading)
                            .frame(minHeight: 112, alignment: .topLeading)
                            .padding(DSSpacing.sm)
                            .background(Color.dsSurfaceMuted, in: RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("应用到当前沙盒")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .dsSurface(.grouped)
    }

    private var evaluatorSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            sectionTitle("真实文本审阅", icon: "brain.head.profile")
            Text("调用当前模型，验证“文本 → 社会信号 → 确定性算法”的完整前半链路。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("角色上一句话（可选）", text: $evaluatorContext, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            TextField("用户回复", text: $evaluatorMessage, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)

            Button {
                Task { await evaluateText() }
            } label: {
                if isEvaluating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("分析并应用到沙盒", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isEvaluating || evaluatorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let evaluatorResult {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(evaluatorResult.relationship.reasonZh)
                        .font(.subheadline.weight(.semibold))
                    signalSummary(evaluatorResult.relationship)
                    Text(evaluatorResult.coachReview.hasIssues ? "语言点评发现问题，但不会直接扣好感度。" : "未发现需要提示的语言问题。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(DSSpacing.sm)
                .background(Color.dsSurfaceMuted, in: RoundedRectangle(cornerRadius: DSRadius.inline, style: .continuous))
            }
            if let evaluatorError {
                Label(evaluatorError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.dsDanger)
            }
        }
        .dsSurface(.grouped)
    }

    private var timeAndBatchSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            sectionTitle("时间与压力测试", icon: "clock.arrow.circlepath")
            Text(simulatedDate.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack {
                    timeButton("+1天", days: 1)
                    timeButton("+7天", days: 7)
                    timeButton("+30天", days: 30)
                    timeButton("+90天", days: 90)
                    timeButton("+1年", days: 365)
                }
            }
            .scrollIndicators(.hidden)

            VStack(spacing: DSSpacing.xs) {
                batchButton("连续 10 次高质量互动", icon: "arrow.up.heart", action: runPositiveBatch)
                batchButton("连续 30 次普通寒暄", icon: "bubble.left.and.bubble.right", action: runNeutralBatch)
                batchButton("严重越界 → 真诚修复", icon: "bandage", action: runConflictRepair)
                batchButton("运行自动回归矩阵", icon: "checklist.checked", action: runAutomatedSuite)
            }
        }
        .dsSurface(.grouped)
    }

    private var manualSignalSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            sectionTitle("手动社会信号", icon: "slider.horizontal.3")
            Text("有正负方向的量使用 −1…1，其余使用 0…1。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            signalSlider("温暖", value: $warmth, range: -1...1)
            signalSlider("回应性", value: $responsiveness, range: 0...1)
            signalSlider("尊重", value: $respect, range: -1...1)
            signalSlider("同理心", value: $empathy, range: 0...1)
            signalSlider("互惠", value: $reciprocity, range: -1...1)
            signalSlider("自我披露", value: $disclosure, range: 0...1)
            signalSlider("共鸣", value: $resonance, range: -1...1)
            signalSlider("投入", value: $engagement, range: 0...1)
            signalSlider("越界伤害", value: $boundaryHarm, range: 0...1, tint: .dsDanger)
            signalSlider("修复", value: $repair, range: 0...1, tint: .dsSuccess)
            signalSlider("事件重要性", value: $significance, range: 0...1)
            signalSlider("判断置信度", value: $confidence, range: 0...1)
            TextField("变化原因", text: $manualReason)
                .textFieldStyle(.roundedBorder)
            Button("应用手动信号", systemImage: "play.fill") {
                apply(manualSignal)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .dsSurface(.grouped)
    }

    private var invariantSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            sectionTitle("约束检查", icon: "checkmark.shield")
            ForEach(currentInvariants + assertions) { assertion in
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: assertion.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(assertion.passed ? Color.dsSuccess : Color.dsDanger)
                    Text(assertion.title)
                        .font(.subheadline)
                    Spacer()
                    Text(assertion.detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .dsSurface(.grouped)
    }

    private var eventHistorySection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            sectionTitle("最近变化", icon: "list.bullet.rectangle")
            if sandbox.recentEvents.isEmpty {
                Text("尚无达到记录阈值的互动。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sandbox.recentEvents.reversed()) { event in
                    HStack(alignment: .top, spacing: DSSpacing.sm) {
                        Text(signed(event.delta))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(deltaColor(event.delta))
                            .frame(width: 48, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.reasonZh)
                                .font(.subheadline)
                            Text("\(event.source.labTitle) · \(event.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    if event.id != sandbox.recentEvents.first?.id {
                        Divider()
                    }
                }
            }
        }
        .dsSurface(.grouped)
    }

    private var persistenceSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            sectionTitle("真实持久化验证", icon: "externaldrive")
            Text("仅用于验证联系人详情、通知和同步载荷。写入会覆盖所选角色当前状态。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if hasFutureInteraction {
                Label("沙盒包含未来互动时间，已禁止写入。请重新载入真实状态或重置初识。", systemImage: "clock.badge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(Color.dsWarning)
            }
            Button("写入所选角色并回读验证", systemImage: "externaldrive.badge.checkmark") {
                showsPersistenceConfirmation = true
            }
            .buttonStyle(.bordered)
            .disabled(selectedCharacter == nil || hasFutureInteraction)
            if let persistenceMessage {
                Text(persistenceMessage)
                    .font(.footnote)
                    .foregroundStyle(persistenceMessage.hasPrefix("成功") ? Color.dsSuccess : Color.dsDanger)
            }
        }
        .dsSurface(.grouped)
    }

    private var manualSignal: RelationshipSignal {
        RelationshipSignal(
            warmth: warmth,
            responsiveness: responsiveness,
            respect: respect,
            empathy: empathy,
            reciprocity: reciprocity,
            disclosure: disclosure,
            resonance: resonance,
            engagement: engagement,
            boundaryHarm: boundaryHarm,
            repair: repair,
            significance: significance,
            confidence: confidence,
            reasonZh: manualReason
        )
    }

    private var currentInvariants: [RelationshipLabAssertion] {
        let dimensions = [sandbox.familiarity, sandbox.trust, sandbox.rapport, sandbox.care, sandbox.respect]
        return [
            .init(title: "好感度在 0…150", passed: (0...150).contains(sandbox.affinity), detail: number(sandbox.affinity)),
            .init(title: "长期下限不高于当前值", passed: sandbox.bondFloor <= sandbox.affinity && sandbox.bondFloor >= 0, detail: number(sandbox.bondFloor)),
            .init(title: "五个维度在 0…1", passed: dimensions.allSatisfy { (0...1).contains($0) }, detail: "\(dimensions.count)/5"),
            .init(title: "张力在 0…1", passed: (0...1).contains(sandbox.unresolvedStrain), detail: percent(sandbox.unresolvedStrain)),
            .init(title: "每日正向收益 ≤ 4", passed: sandbox.positiveGainToday <= 4.000_001, detail: number(sandbox.positiveGainToday)),
            .init(title: "每日修复收益 ≤ 2", passed: (sandbox.repairGainToday ?? 0) <= 2.000_001, detail: number(sandbox.repairGainToday ?? 0)),
            .init(title: "变化记录最多 24 条", passed: sandbox.recentEvents.count <= 24, detail: "\(sandbox.recentEvents.count)/24"),
            .init(title: "结算去重账本最多 64 条", passed: (sandbox.recentEvaluatedMessageIDs ?? []).count <= 64, detail: "\((sandbox.recentEvaluatedMessageIDs ?? []).count)/64"),
        ]
    }

    @ViewBuilder
    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private func metric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dimension(_ title: String, _ value: Double) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Text(title)
                .font(.subheadline)
                .frame(width: 72, alignment: .leading)
            ProgressView(value: value)
                .tint(Color.dsSky)
            Text(percent(value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func signalSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        tint: Color = .dsSky
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .tint(tint)
        }
    }

    private func signalSummary(_ signal: RelationshipSignal) -> some View {
        ViewThatFits {
            HStack {
                Text("温暖 \(number(signal.warmth))")
                Text("尊重 \(number(signal.respect))")
                Text("越界 \(number(signal.boundaryHarm))")
                Text("重要性 \(number(signal.significance))")
            }
            VStack(alignment: .leading) {
                Text("温暖 \(number(signal.warmth)) · 尊重 \(number(signal.respect))")
                Text("越界 \(number(signal.boundaryHarm)) · 重要性 \(number(signal.significance))")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func timeButton(_ title: String, days: Int) -> some View {
        Button(title) { advance(days: days) }
            .buttonStyle(.bordered)
    }

    private func batchButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    @MainActor
    private func loadCharacters() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let values = try await rosterStore.friends()
            characters = values.sorted { $0.card.name.localizedStandardCompare($1.card.name) == .orderedAscending }
            if selectedCharacterID == nil || !characters.contains(where: { $0.id == selectedCharacterID }) {
                selectedCharacterID = characters.first?.id
            }
            loadSelectedRelationship()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadSelectedRelationship() {
        guard let selectedCharacter else { return }
        baseline = selectedCharacter.relationship
        sandbox = selectedCharacter.relationship
        simulatedDate = max(Date.now, selectedCharacter.relationship.lastEvaluatedMessageAt?.addingTimeInterval(1) ?? .distantPast)
        eventSequence = max(selectedCharacter.relationship.lastEvaluatedOrderIndex + 1, 0)
        assertions = []
        persistenceMessage = nil
        evaluatorResult = nil
    }

    private func resetToInitial() {
        baseline = .initial
        sandbox = .initial
        simulatedDate = .now
        eventSequence = 0
        assertions = []
        persistenceMessage = nil
        evaluatorResult = nil
    }

    private func apply(_ signal: RelationshipSignal) {
        let eventDate = simulatedDate.addingTimeInterval(60)
        let updated = RelationshipEngine.apply(
            signal,
            to: sandbox,
            source: source,
            messageID: UUID(),
            messageCreatedAt: eventDate,
            messageOrderIndex: eventSequence,
            at: eventDate
        )
        withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
            sandbox = updated
            simulatedDate = eventDate
            eventSequence += 1
            assertions = []
        }
    }

    private func advance(days: Int) {
        withAnimation(reduceMotion ? nil : DSAnimation.snappy) {
            simulatedDate = simulatedDate.addingTimeInterval(Double(days) * 86_400)
            assertions = []
        }
    }

    @MainActor
    private func evaluateText() async {
        guard let character = selectedCharacter else { return }
        isEvaluating = true
        evaluatorError = nil
        defer { isEvaluating = false }
        let eventDate = simulatedDate.addingTimeInterval(60)
        let message = MessageDTO(
            id: UUID(),
            role: .user,
            kind: .text,
            text: evaluatorMessage,
            orderIndex: eventSequence,
            createdAt: eventDate
        )
        let history: [MessageDTO] = evaluatorContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? []
            : [MessageDTO(
                id: UUID(),
                role: .assistant,
                kind: .text,
                text: evaluatorContext,
                orderIndex: max(eventSequence - 1, 0),
                createdAt: eventDate.addingTimeInterval(-30)
            )]
        do {
            let result = try await RelationshipService(llm: llm, rosterStore: rosterStore).evaluate(
                character: character,
                history: history,
                userMessage: message
            )
            evaluatorResult = result
            apply(result.relationship)
        } catch {
            evaluatorError = "分析失败：\(error.localizedDescription)"
        }
    }

    private func runPositiveBatch() {
        for _ in 0..<10 { apply(RelationshipLabFixtures.highQuality) }
    }

    private func runNeutralBatch() {
        for _ in 0..<30 { apply(RelationshipLabFixtures.casual) }
    }

    private func runConflictRepair() {
        apply(RelationshipLabFixtures.boundaryViolation)
        apply(RelationshipLabFixtures.repair)
    }

    private func runAutomatedSuite() {
        assertions = RelationshipLabFixtures.automatedAssertions()
    }

    @MainActor
    private func persistSandbox() async {
        guard let selectedCharacter else { return }
        do {
            guard let latest = try await rosterStore.character(id: selectedCharacter.id) else {
                persistenceMessage = "失败：角色不存在"
                return
            }
            var candidate = sandbox
            candidate.revision = latest.relationship.revision + 1
            let saved = try await rosterStore.updateRelationship(
                characterID: selectedCharacter.id,
                snapshot: candidate,
                expectedRevision: latest.relationship.revision
            )
            guard saved, let verified = try await rosterStore.character(id: selectedCharacter.id) else {
                persistenceMessage = "失败：状态已被其他任务更新，请重新载入"
                return
            }
            sandbox = verified.relationship
            baseline = verified.relationship
            if let index = characters.firstIndex(where: { $0.id == selectedCharacter.id }) {
                characters[index] = verified
            }
            persistenceMessage = "成功：已写入并从数据库回读，修订号 \(verified.relationship.revision)"
        } catch {
            persistenceMessage = "失败：\(error.localizedDescription)"
        }
    }

    private func signed(_ value: Double) -> String {
        value >= 0 ? "+\(number(value))" : number(value)
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private func percent(_ value: Double) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private func deltaColor(_ value: Double) -> Color {
        value > 0.001 ? .dsSuccess : (value < -0.001 ? .dsDanger : .secondary)
    }
}

private struct RelationshipLabScenario: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let signal: RelationshipSignal
}

private struct RelationshipLabAssertion: Identifiable {
    let title: String
    let passed: Bool
    let detail: String

    var id: String { title }
}

private enum RelationshipLabFixtures {
    static let highQuality = signal(
        warmth: 0.9, responsiveness: 0.95, respect: 0.95, empathy: 0.8,
        reciprocity: 0.85, disclosure: 0.55, resonance: 0.8, engagement: 0.95,
        significance: 0.8, reason: "认真回应并分享了重要经历"
    )
    static let casual = signal(
        warmth: 0.25, responsiveness: 0.45, respect: 0.75, empathy: 0.1,
        reciprocity: 0.25, disclosure: 0.05, resonance: 0.1, engagement: 0.35,
        significance: 0.12, reason: "一次普通的日常寒暄"
    )
    static let respectfulDisagreement = signal(
        warmth: 0.15, responsiveness: 0.85, respect: 0.95, empathy: 0.45,
        reciprocity: 0.5, disclosure: 0.15, resonance: -0.25, engagement: 0.8,
        significance: 0.45, reason: "观点不同但认真倾听并保持尊重"
    )
    static let englishMistakes = signal(
        warmth: 0.7, responsiveness: 0.8, respect: 0.9, empathy: 0.3,
        reciprocity: 0.65, disclosure: 0.3, resonance: 0.55, engagement: 0.85,
        significance: 0.55, reason: "表达不流利但交流真诚投入"
    )
    static let dismissive = signal(
        warmth: -0.5, responsiveness: 0.1, respect: -0.55, empathy: 0,
        reciprocity: -0.4, disclosure: 0, resonance: -0.4, engagement: 0.2,
        boundaryHarm: 0.15, significance: 0.55, reason: "回应冷淡并带有轻视"
    )
    static let boundaryViolation = signal(
        warmth: -0.9, responsiveness: 0.05, respect: -1, empathy: 0,
        reciprocity: -0.8, disclosure: 0, resonance: -0.6, engagement: 0.8,
        boundaryHarm: 1, significance: 1, reason: "明确无视边界并造成伤害"
    )
    static let repair = signal(
        warmth: 0.65, responsiveness: 0.95, respect: 0.98, empathy: 0.95,
        reciprocity: 0.75, disclosure: 0.5, resonance: 0.2, engagement: 0.9,
        repair: 0.95, significance: 0.9, reason: "真诚道歉并承担影响"
    )

    @MainActor
    static var scenarios: [RelationshipLabScenario] {
        [
            .init(id: "quality", title: "聊得很投机", subtitle: "温暖、互惠且认真回应", icon: "heart.fill", color: .dsSuccess, signal: highQuality),
            .init(id: "casual", title: "普通寒暄", subtitle: "检查中性基线和抗刷取", icon: "bubble.left", color: .dsSky, signal: casual),
            .init(id: "disagree", title: "尊重地分歧", subtitle: "不同观点不应被惩罚", icon: "arrow.left.arrow.right", color: .dsCyan, signal: respectfulDisagreement),
            .init(id: "english", title: "英语不流利", subtitle: "语言错误不影响关系", icon: "text.badge.xmark", color: .dsQuiz, signal: englishMistakes),
            .init(id: "dismissive", title: "敷衍轻视", subtitle: "低质量且不够尊重", icon: "hand.thumbsdown", color: .dsWarning, signal: dismissive),
            .init(id: "harm", title: "严重越界", subtitle: "高伤害、信任和下限受损", icon: "exclamationmark.octagon.fill", color: .dsDanger, signal: boundaryViolation),
            .init(id: "repair", title: "真诚修复", subtitle: "部分恢复但不抹去伤害", icon: "bandage.fill", color: .dsSuccess, signal: repair),
        ]
    }

    static func automatedAssertions() -> [RelationshipLabAssertion] {
        let now = Date(timeIntervalSince1970: 2_100_000_000)
        let positive = apply(highQuality, to: .initial, index: 0, at: now)

        var repeated = RelationshipSnapshot.initial
        for index in 0..<30 {
            repeated = apply(highQuality, to: repeated, index: index, at: now.addingTimeInterval(Double(index * 60)))
        }

        let healthy = RelationshipSnapshot(
            affinity: 90, bondFloor: 42, familiarity: 0.7, trust: 0.75,
            rapport: 0.72, care: 0.68, respect: 0.8,
            lastInteractionAt: now.addingTimeInterval(-60)
        )
        let harmed = apply(boundaryViolation, to: healthy, index: 1, at: now)
        let repaired = apply(repair, to: harmed, index: 2, at: now.addingTimeInterval(60))
        let afterYear = healthy.projectedAffinity(at: now.addingTimeInterval(365 * 86_400))

        let duplicateResult = RelationshipEngine.apply(
            highQuality,
            to: positive,
            source: .textChat,
            messageID: positive.lastEvaluatedMessageID ?? UUID(),
            messageCreatedAt: now.addingTimeInterval(-1),
            messageOrderIndex: 99,
            at: now.addingTimeInterval(120)
        )
        let outOfOrderResult = RelationshipEngine.apply(
            highQuality,
            to: positive,
            source: .textChat,
            messageID: UUID(),
            messageCreatedAt: now.addingTimeInterval(-1),
            messageOrderIndex: 99,
            at: now.addingTimeInterval(120)
        )
        let ordinaryTension = apply(
            signal(
                warmth: -0.45, responsiveness: 0.15, respect: -0.35, empathy: 0.1,
                reciprocity: -0.3, disclosure: 0, resonance: -0.35, engagement: 0.25,
                significance: 0.35, reason: "不愉快但没有越界"
            ),
            to: healthy,
            index: 3,
            at: now.addingTimeInterval(120)
        )
        let contradictoryHarm = apply(
            signal(
                warmth: 1, responsiveness: 1, respect: 1, empathy: 1,
                reciprocity: 1, disclosure: 1, resonance: 1, engagement: 1,
                boundaryHarm: 1, repair: 1, significance: 1,
                reason: "内部矛盾的极端信号"
            ),
            to: healthy,
            index: 4,
            at: now.addingTimeInterval(180)
        )
        let noInformation = apply(
            signal(
                warmth: 0, responsiveness: 0, respect: 0, empathy: 0,
                reciprocity: 0, disclosure: 0, resonance: 0, engagement: 0,
                significance: 0, reason: "无信息量重复"
            ),
            to: .initial,
            index: 0,
            at: now
        )

        return [
            .init(title: "优质互动产生正向变化", passed: positive.affinity > 10, detail: "+\((positive.affinity - 10).formatted(.number.precision(.fractionLength(2))))"),
            .init(title: "30 次互动仍受每日上限约束", passed: repeated.positiveGainToday <= 4.000_001, detail: repeated.positiveGainToday.formatted(.number.precision(.fractionLength(2)))),
            .init(title: "严重越界明显降低关系", passed: harmed.affinity < healthy.affinity - 5 && harmed.unresolvedStrain > 0.2, detail: (harmed.affinity - healthy.affinity).formatted(.number.precision(.fractionLength(2)))),
            .init(title: "修复有效但不会一次复原", passed: repaired.affinity > harmed.affinity && repaired.affinity < healthy.affinity, detail: repaired.affinity.formatted(.number.precision(.fractionLength(2)))),
            .init(title: "一年失联不跌破长期下限", passed: afterYear >= healthy.bondFloor && afterYear < healthy.affinity, detail: afterYear.formatted(.number.precision(.fractionLength(2)))),
            .init(title: "同一消息不会重复结算", passed: duplicateResult == positive, detail: duplicateResult == positive ? "已忽略" : "失败"),
            .init(title: "乱序的不同消息仍会结算", passed: outOfOrderResult.interactionCount == positive.interactionCount + 1, detail: "\(outOfOrderResult.interactionCount) 次"),
            .init(title: "普通摩擦不侵蚀长期纽带", passed: ordinaryTension.bondFloor == healthy.bondFloor, detail: ordinaryTension.bondFloor.formatted(.number.precision(.fractionLength(2)))),
            .init(title: "越界压过矛盾的正向字段", passed: contradictoryHarm.affinity < healthy.affinity && contradictoryHarm.trust < healthy.trust, detail: (contradictoryHarm.affinity - healthy.affinity).formatted(.number.precision(.fractionLength(2)))),
            .init(title: "无信息量互动不改变关系维度", passed: dimensions(of: noInformation) == dimensions(of: .initial), detail: noInformation.familiarity.formatted(.number.precision(.fractionLength(3)))),
        ]
    }

    private static func dimensions(of snapshot: RelationshipSnapshot) -> [Double] {
        [snapshot.familiarity, snapshot.trust, snapshot.rapport, snapshot.care, snapshot.respect, snapshot.unresolvedStrain]
    }

    private static func apply(
        _ signal: RelationshipSignal,
        to snapshot: RelationshipSnapshot,
        index: Int,
        at date: Date
    ) -> RelationshipSnapshot {
        RelationshipEngine.apply(
            signal,
            to: snapshot,
            source: .textChat,
            messageID: UUID(),
            messageCreatedAt: date,
            messageOrderIndex: index,
            at: date
        )
    }

    private static func signal(
        warmth: Double,
        responsiveness: Double,
        respect: Double,
        empathy: Double,
        reciprocity: Double,
        disclosure: Double,
        resonance: Double,
        engagement: Double,
        boundaryHarm: Double = 0,
        repair: Double = 0,
        significance: Double,
        reason: String
    ) -> RelationshipSignal {
        RelationshipSignal(
            warmth: warmth,
            responsiveness: responsiveness,
            respect: respect,
            empathy: empathy,
            reciprocity: reciprocity,
            disclosure: disclosure,
            resonance: resonance,
            engagement: engagement,
            boundaryHarm: boundaryHarm,
            repair: repair,
            significance: significance,
            confidence: 0.95,
            reasonZh: reason
        )
    }
}

private extension RelationshipEventRecord.Source {
    var labTitle: String {
        switch self {
        case .textChat: "文字"
        case .voiceChat: "语音"
        case .sharedActivity: "活动"
        case .story: "剧情"
        }
    }
}
#endif
