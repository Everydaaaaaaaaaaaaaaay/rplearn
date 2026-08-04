import MascotKit
import Testing

@Suite(.serialized)
@MainActor
struct MascotAnimationControllerTests {
    @Test("动画控制器可通过语义和事件驱动同一模型")
    func semanticAndEventRequests() {
        let controller = MascotAnimationController()

        #expect(controller.request(.semantic(.success)))
        controller.prepareIfNeeded()
        #expect(controller.loadState == .ready)
        #expect(controller.currentAnimation == .celebrate)

        #expect(controller.request(.event(.speechStarted)))
        #expect(controller.currentAnimation == .talk)

        #expect(controller.request(.event(.speechFinished)))
        #expect(controller.currentAnimation == .idle)
    }

    @Test("未知能力返回可诊断错误且不打断当前动画")
    func unavailableRequestsAreDiagnosable() {
        let controller = MascotAnimationController()
        controller.prepareIfNeeded()

        #expect(!controller.request(.semantic("unknown")))
        #expect(controller.lastPlaybackError == .unresolvedSemantic("unknown"))
        #expect(controller.currentAnimation == .idle)

        #expect(!controller.request(.event("unknown")))
        #expect(controller.lastPlaybackError == .unboundEvent("unknown"))
        #expect(controller.currentAnimation == .idle)
    }

    @Test("暂停和停止是独立的生命周期能力")
    func pauseAndStop() {
        let controller = MascotAnimationController()
        controller.setPaused(true)
        controller.prepareIfNeeded()

        #expect(controller.isPaused)
        #expect(controller.content?.animationPlayer(for: .idle)?.paused == true)

        controller.setPaused(false)
        #expect(!controller.isPaused)
        #expect(controller.content?.animationPlayer(for: .idle)?.paused == false)

        controller.stop()
        #expect(controller.currentAnimation == nil)
        #expect(controller.loadState == .ready)
    }
}
