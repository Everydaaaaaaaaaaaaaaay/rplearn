import Combine
import DomainKit
import Foundation

/// App-owned lifetime: Tab/navigation disappearance never owns an action request.
@MainActor
public final class ActivityJourneyCoordinator: ObservableObject {
    @Published private(set) var model: SocialEncounterModel?
    @Published public private(set) var hasUnreadResult = false
    private var observation: AnyCancellable?
    private var deadlineTask: Task<Void, Never>?
    private var viewing = false
    private var resultWasSeen = false
    public init() {}

    public var isPreparing: Bool { model?.started == true && model?.canReveal == false }
    public var isRunning: Bool { model?.started == true && model?.completed == false }
    public var activeActivity: SceneActivity? { model?.activity }

    func prepare(activity: SceneActivity, region: Region, deps: HomeDependencies, namespace: String) {
        if model?.started == true { return }
        let next = SocialEncounterModel(activity: activity, region: region, deps: deps, namespace: namespace)
        resultWasSeen = false
        model = next
        observation = next.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    func start() {
        guard let model else { return }
        model.start()
        guard let deadline = model.revealAt, deadlineTask == nil else { return }
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
    func setViewing(_ visible: Bool) {
        viewing = visible
        if visible { hasUnreadResult = false }
        else { model?.stopSpeech() }
        refresh()
    }
    private func refresh() {
        if let model, model.canReveal {
            if viewing { resultWasSeen = true; hasUnreadResult = false }
            else if !resultWasSeen { hasUnreadResult = true }
        }
        objectWillChange.send()
    }
    public func reset() {
        observation = nil
        deadlineTask?.cancel(); deadlineTask = nil
        model?.pause(); model = nil
        hasUnreadResult = false
        resultWasSeen = false
    }
}
