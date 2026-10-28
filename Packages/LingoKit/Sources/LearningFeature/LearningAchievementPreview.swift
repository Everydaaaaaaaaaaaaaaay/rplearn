#if DEBUG
import BackendKit
import CoreKit
import PersistenceKit
import SwiftUI

/// Uses the production page and reward presentation path with an isolated memory service.
public struct LearningAchievementPreview: View {
    private let character: CharacterDTO
    private let level: String
    private let currentRegionID: @Sendable () async -> String?
    @State private var session: LearningAchievementPreviewSession
    @State private var startingStars = 3
    @State private var updating = false
    @State private var showPromotion = false
    private var model: CharacterLearningModel { session.model }
    private var nextLevel: String? {
        let levels = DifficultyLevel.allCases.map(\.rawValue)
        guard let index = levels.firstIndex(of: level), index + 1 < levels.count else { return nil }
        return levels[index + 1]
    }
    public init(character: CharacterDTO, level: String = "senior3",
                currentRegionID: @escaping @Sendable () async -> String? = { "london" }) {
        self.character = character; self.level = level; self.currentRegionID = currentRegionID
        _session = State(initialValue: LearningAchievementPreviewSession(character: character, level: level))
    }
    public var body: some View {
        CharacterLearningView(character: character, previewModel: model, currentRegionID: currentRegionID)
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(model.starAward == nil ? "播放升星" : "跳过升星") {
                        if model.starAward != nil { model.consumeStarAward() }
                        else { Task { await play(count: 1) } }
                    }
                    .disabled(updating || model.isBusy || model.journey == nil)
                    .accessibilityIdentifier("learning.achievement.play-star")
                    Menu {
                        Picker("起始星数", selection: $startingStars) {
                            ForEach([0, 3, 8], id: \.self) { count in Text("\(count) 颗星").tag(count) }
                        }.pickerStyle(.inline)
                        Button("多星边界测试") { Task { await play(count: 3) } }
                            .accessibilityIdentifier("learning.achievement.play-multiple")
                        Text("本地预览，不改变账号进度。")
                    } label: { Image(systemName: "slider.horizontal.3") }
                    .disabled(updating || model.isBusy || model.starAward != nil || model.journey == nil)
                    .accessibilityLabel("预览设置")
                    .accessibilityIdentifier("learning.achievement.settings")
                    Button {
                        model.consumeStarAward(); showPromotion = true
                    } label: { Image(systemName: "graduationcap") }
                    .disabled(updating || nextLevel == nil)
                    .accessibilityLabel("预览晋升仪式")
                    .accessibilityIdentifier("learning.achievement.play-promotion")
                }
            }
            .onChange(of: startingStars) { _, _ in Task { await reset() } }
            .fullScreenCover(isPresented: $showPromotion) {
                if let nextLevel {
                    LearningPromotionCelebration(fromLevel: level, toLevel: nextLevel,
                        message: "Take your time. We can read it together.",
                        close: { showPromotion = false }, continueJourney: { showPromotion = false })
                }
            }
    }
    private func reset() async {
        guard !updating else { return }
        updating = true; defer { updating = false }
        model.consumeStarAward()
        await session.service.set(stars: startingStars, nearNext: true)
        await model.load()
    }
    private func play(count: Int) async {
        guard !updating else { return }
        updating = true; defer { updating = false }
        model.consumeStarAward()
        await session.service.set(stars: startingStars, nearNext: true)
        await model.load()
        await model.previewReward(toStars: min(9, startingStars + count))
    }
}

@MainActor private final class LearningAchievementPreviewSession {
    let service: LearningAchievementPreviewService
    let model: CharacterLearningModel
    init(character: CharacterDTO, level: String) {
        service = LearningAchievementPreviewService(character: character, level: level)
        model = CharacterLearningModel(characterID: character.id, service: service)
    }
}

/// No account store, transport or persisted state is available to this service.
actor LearningAchievementPreviewService: LearningServing, LearningDirectionServing {
    private let characterID: UUID
    private let role: String
    private let level: String
    private let cycleID = UUID()
    private var points = 3 * 60 + 59
    init(character: CharacterDTO, level: String) {
        characterID = character.id; self.level = level
        role = character.card.name.components(separatedBy: " ").first?.lowercased() ?? "oliver"
    }
    func set(stars: Int, nearNext: Bool) {
        let stars = min(9, max(0, stars))
        points = stars * 60 + (nearNext && stars < 9 ? 59 : 0)
    }
    func learningCharacter(_ id: UUID) throws -> BackendLearningCharacter {
        try decode(["characterId": characterID.uuidString, "roleKey": role, "cycleId": cycleID.uuidString,
                    "characters": 500, "threshold": 500, "revision": 1, "level": level, "availableUnits": 1])
    }
    func learningJourney() throws -> LearningJourney {
        try decode(["currentLevel": level,
            "policy": ["version": 1, "characterThreshold": 500, "pointsPerQuestion": 1, "pointsPerStar": 60, "starsPerLevel": 9],
            "levels": [["level": level, "points": points, "displayPoints": points, "targetPoints": 540,
                        "stars": points / 60, "currentStarPoints": points == 540 ? 60 : points % 60, "pointsPerStar": 60]]])
    }
    func learningHistory(_ id: UUID, cursor: String?) throws -> LearningHistory {
        try decode(["items": [["id": "20000000-0000-4000-8000-000000000001", "title": "综合练习 · 在书店挑选一本新书",
            "level": level, "startedAt": "2026-10-28T00:00:00Z", "firstCompletedAt": "2026-10-28T00:10:00Z",
            "correctCount": 6, "questionCount": 6, "earnedPoints": 6]]])
    }
    func learningDirections() -> LearningDirections {
        .init(selectedDirection: "general", revision: 1, directions: [.init(id: "general", title: "通用英语", status: "available")])
    }
    func selectLearningDirection(_ direction: String, requestID: UUID, expectedRevision: Int) -> LearningDirections { learningDirections() }
    func startLearning(_ id: UUID, requestID: UUID) throws -> LearningStart { throw unavailable }
    func learningAttempt(_ id: UUID) throws -> LearningAttempt { throw unavailable }
    func answerLearning(_ id: UUID, command: LearningAnswerCommand) throws -> LearningAnswerReceipt { throw unavailable }
    func finishLearning(_ attempt: LearningAttempt, requestID: UUID, skipRemaining: Bool) throws -> LearningAttempt { throw unavailable }
    func retryLearning(_ attempt: LearningAttempt, requestID: UUID) throws -> LearningAttempt { throw unavailable }
    private var unavailable: BackendClientError {
        .api(code: "PREVIEW_ONLY", message: "这是动效预览，请在学习实测中开始真实练习。", requestID: nil, status: 400)
    }
    private func decode<T: Decodable>(_ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
#endif
