import Foundation
import Observation
@preconcurrency import SceneKit

/// 上层触发动画时可选择精确片段、产品语义或资源目录中的事件映射。
public enum MascotAnimationRequest: Equatable, Sendable {
    case animation(MascotAnimationID)
    case semantic(MascotAnimationSemantic)
    case event(MascotEventID)
}

public enum MascotPlaybackError: LocalizedError, Equatable {
    case unavailableAnimation(MascotAnimationID)
    case unresolvedSemantic(MascotAnimationSemantic)
    case unboundEvent(MascotEventID)

    public var errorDescription: String? {
        switch self {
        case let .unavailableAnimation(id):
            "吉祥物不包含动画：\(id.rawValue)"
        case let .unresolvedSemantic(semantic):
            "吉祥物不支持动画语义：\(semantic.rawValue)"
        case let .unboundEvent(event):
            "吉祥物事件没有绑定动画：\(event.rawValue)"
        }
    }
}

public enum MascotLoadState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(String)
}

/// 吉祥物播放状态机。业务层通过稳定请求驱动它，不直接管理 SceneKit 播放器。
@MainActor
@Observable
public final class MascotAnimationController {
    public private(set) var loadState: MascotLoadState = .idle
    public private(set) var content: SceneKitMascotContent?
    public private(set) var currentAnimation: MascotAnimationID?
    public private(set) var lastPlaybackError: MascotPlaybackError?
    public private(set) var isPaused = false

    private let assetID: MascotAssetID
    private let configuration: MascotRenderConfiguration
    private let loader: SceneKitMascotLoader
    private var pendingRequest: MascotAnimationRequest
    private var automaticReturnTask: Task<Void, Never>?

    public init(
        assetID: MascotAssetID = .gugu,
        configuration: MascotRenderConfiguration = .appDefault,
        initialAnimation: MascotAnimationRequest = .semantic(.idle),
        assetProvider: any MascotResourceProviding =
            BundledMascotResourceProvider.packageResources
    ) {
        self.assetID = assetID
        self.configuration = configuration
        self.pendingRequest = initialAnimation
        self.loader = SceneKitMascotLoader(assetProvider: assetProvider)
    }

    /// 首次显示时加载模型。重复调用不会重新解析或打断正在播放的动画。
    public func prepareIfNeeded() {
        guard content == nil, loadState != .loading else { return }
        loadState = .loading
        do {
            let loadedContent = try loader.load(assetID, configuration: configuration)
            content = loadedContent
            loadState = .ready
            _ = activate(pendingRequest, in: loadedContent)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// 清除失败或旧实例并重新加载；资源热更新和预览工具可显式使用。
    public func reload() {
        stop()
        content = nil
        loadState = .idle
        prepareIfNeeded()
    }

    /// 请求一个动画。模型尚未就绪时会记住请求，并在加载完成后执行。
    @discardableResult
    public func request(_ request: MascotAnimationRequest) -> Bool {
        pendingRequest = request
        guard let content else {
            lastPlaybackError = nil
            return true
        }
        return activate(request, in: content)
    }

    /// 暂停时冻结当前姿态并取消自动回落计时，恢复后从当前片段继续。
    public func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        automaticReturnTask?.cancel()
        automaticReturnTask = nil

        guard let content else { return }
        if paused {
            for id in content.availableAnimations {
                content.animationPlayer(for: id)?.paused = true
            }
        } else if let currentAnimation,
                  let player = content.animationPlayer(for: currentAnimation)
        {
            player.paused = false
            if let clip = content.animationCatalog.clip(currentAnimation) {
                scheduleAutomaticReturn(for: clip)
            }
        }
    }

    /// 停止全部片段；内容仍然保留，可在页面重新出现时立即播放。
    public func stop() {
        automaticReturnTask?.cancel()
        automaticReturnTask = nil
        guard let content else {
            currentAnimation = nil
            return
        }
        for id in content.availableAnimations {
            content.animationPlayer(for: id)?.stop()
        }
        currentAnimation = nil
    }

    private func activate(
        _ request: MascotAnimationRequest,
        in content: SceneKitMascotContent
    ) -> Bool {
        let animationID: MascotAnimationID
        switch request {
        case let .animation(id):
            animationID = id
        case let .semantic(semantic):
            guard let resolved = content.animationCatalog.animation(for: semantic) else {
                lastPlaybackError = .unresolvedSemantic(semantic)
                return false
            }
            animationID = resolved
        case let .event(event):
            guard let resolved = content.animationCatalog.animation(for: event) else {
                lastPlaybackError = .unboundEvent(event)
                return false
            }
            animationID = resolved
        }

        guard
            let clip = content.animationCatalog.clip(animationID),
            let player = content.animationPlayer(for: animationID)
        else {
            lastPlaybackError = .unavailableAnimation(animationID)
            return false
        }

        if currentAnimation == animationID, clip.repeats {
            player.paused = isPaused
            lastPlaybackError = nil
            return true
        }

        automaticReturnTask?.cancel()
        automaticReturnTask = nil
        if let currentAnimation,
           let currentPlayer = content.animationPlayer(for: currentAnimation)
        {
            let blendOut = content.animationCatalog.clip(currentAnimation)?.crossfadeOut ?? 0
            currentPlayer.stop(withBlendOutDuration: blendOut)
        }

        player.stop()
        player.play()
        player.paused = isPaused
        currentAnimation = animationID
        lastPlaybackError = nil
        scheduleAutomaticReturn(for: clip)
        return true
    }

    private func scheduleAutomaticReturn(for clip: MascotAnimationClip) {
        guard !isPaused, !clip.repeats, let returnTo = clip.returnTo else { return }
        automaticReturnTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(clip.duration))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.request(.animation(returnTo))
        }
    }
}
