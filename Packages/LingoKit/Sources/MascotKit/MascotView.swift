import SwiftUI
@preconcurrency import SceneKit

/// SceneKit 的薄 SwiftUI 适配层，只负责展示已加载场景。
@MainActor
public struct MascotSceneView: UIViewRepresentable {
    public let content: SceneKitMascotContent
    public let isPlaybackActive: Bool

    public init(
        content: SceneKitMascotContent,
        isPlaybackActive: Bool = true
    ) {
        self.content = content
        self.isPlaybackActive = isPlaybackActive
    }

    public func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        configure(view)
        return view
    }

    public func updateUIView(_ view: SCNView, context: Context) {
        configure(view)
    }

    public static func dismantleUIView(_ view: SCNView, coordinator: Void) {
        view.isPlaying = false
        view.scene = nil
    }

    private func configure(_ view: SCNView) {
        if view.scene !== content.scene {
            view.scene = content.scene
        }
        view.pointOfView = content.cameraNode
        view.backgroundColor = .clear
        view.isOpaque = false
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = content.preferredFramesPerSecond
        view.rendersContinuously = isPlaybackActive
        view.isPlaying = isPlaybackActive
    }
}

/// 带加载占位、生命周期暂停和系统“减弱动态效果”适配的高层入口。
@MainActor
public struct MascotView<Placeholder: View>: View {
    @Bindable private var controller: MascotAnimationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let animation: MascotAnimationRequest
    private let isPaused: Bool
    private let placeholder: Placeholder

    public init(
        controller: MascotAnimationController,
        animation: MascotAnimationRequest = .semantic(.idle),
        isPaused: Bool = false,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.controller = controller
        self.animation = animation
        self.isPaused = isPaused
        self.placeholder = placeholder()
    }

    public var body: some View {
        ZStack {
            if let content = controller.content {
                MascotSceneView(
                    content: content,
                    isPlaybackActive: !isPaused && !reduceMotion
                )
                .transition(.opacity)
            } else {
                placeholder
            }
        }
        .task {
            controller.setPaused(isPaused || reduceMotion)
            controller.request(animation)
            controller.prepareIfNeeded()
        }
        .onChange(of: animation) { _, newValue in
            controller.request(newValue)
        }
        .onChange(of: isPaused) { _, newValue in
            controller.setPaused(newValue || reduceMotion)
        }
        .onChange(of: reduceMotion) { _, newValue in
            controller.setPaused(isPaused || newValue)
        }
        .onDisappear {
            controller.setPaused(true)
        }
    }
}

public extension MascotView where Placeholder == EmptyView {
    init(
        controller: MascotAnimationController,
        animation: MascotAnimationRequest = .semantic(.idle),
        isPaused: Bool = false
    ) {
        self.init(
            controller: controller,
            animation: animation,
            isPaused: isPaused,
            placeholder: EmptyView.init
        )
    }
}
