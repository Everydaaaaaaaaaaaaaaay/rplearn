import BackendKit
import Foundation
import Observation

/// 每个选项独立保留完整播放记录，同一时间只允许一段声音。
@MainActor @Observable
final class LearningAudioOptionsModel {
    private(set) var players: [String: LearningAudioModel] = [:]
    @ObservationIgnored private let makePlayer: () -> LearningAudioModel
    @ObservationIgnored private var revision = UUID()

    init(makePlayer: @escaping () -> LearningAudioModel) { self.makePlayer = makePlayer }

    var hasListenedToAll: Bool { !players.isEmpty && players.values.allSatisfy(\.hasListened) }

    func prepare(attemptID: UUID, question: LearningQuestion?) async {
        reset()
        guard let question, question.type == .audioChoice else { return }
        let requestRevision = revision
        let options = question.audioOptions ?? []
        for option in options { players[option.id] = makePlayer() }
        for option in options {
            guard revision == requestRevision, !Task.isCancelled else { return }
            await players[option.id]?.prepare(attemptID: attemptID, questionID: question.id, assetID: option.audio.assetId)
        }
    }

    func play(_ id: String, slow: Bool = false) {
        for (key, player) in players where key != id && player.isPlaybackActive { player.stop() }
        guard let player = players[id] else { return }
        if player.state == .playing && !slow { player.stop() }
        else { player.play(slow: slow) }
    }

    func retry(_ option: LearningQuestion.AudioOption, attemptID: UUID, questionID: String) async {
        await players[option.id]?.prepare(attemptID: attemptID, questionID: questionID, assetID: option.audio.assetId)
    }

    func stop(interrupted: Bool = false) {
        for player in players.values where player.isPlaybackActive { player.stop(interrupted: interrupted) }
    }

    func interrupt(except playbackID: UUID?) {
        for player in players.values where player.playbackID != playbackID && player.isPlaybackActive {
            player.stop(interrupted: true)
        }
    }

    func reset() {
        revision = UUID()
        for player in players.values { player.reset() }
        players = [:]
    }
}
