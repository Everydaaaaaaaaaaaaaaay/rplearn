#if DEBUG
import DesignSystem
import SwiftUI

/// 吉祥物形象检查页：咕咕和嘎嘎的全部姿势、常用小尺寸，一屏看完。
/// `UI_TEST_MASCOT_ZOOM=gugu|gaga` 时只放大一只鸟，用于检查细节。
struct DebugMascotGallery: View {
    @Environment(\.dismiss) private var dismiss
    private let zoom = ProcessInfo.processInfo.environment["UI_TEST_MASCOT_ZOOM"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Puff.Palette.page.ignoresSafeArea()
            if let zoom {
                zoomed(zoom == "gaga" ? .gaga : .gugu)
            } else {
                overview
            }
            Button("关闭", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.puffSquish)
                .padding()
        }
    }

    private var overview: some View {
        VStack(spacing: 10) {
            HStack(spacing: 24) {
                PuffMascot(.gugu, pose: .wave, size: 130)
                PuffMascot(.gaga, pose: .wave, size: 130)
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(PuffMascot.Pose.allCases, id: \.self) { pose in
                    cell(.gugu, pose)
                    cell(.gaga, pose)
                }
            }
            HStack(spacing: 14) {
                ForEach([28, 40, 54] as [CGFloat], id: \.self) { size in
                    PuffMascot(.gugu, pose: .happy, size: size, showsShadow: false)
                    PuffMascot(.gaga, pose: .happy, size: size, showsShadow: false)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func cell(_ bird: PuffMascot.Bird, _ pose: PuffMascot.Pose) -> some View {
        VStack(spacing: 0) {
            PuffMascot(bird, pose: pose, size: 78)
            Text(verbatim: "\(pose)")
                .font(.puff(.caption2, Puff.Weight.label))
                .foregroundStyle(Puff.Palette.inkFaint)
        }
    }

    private func zoomed(_ bird: PuffMascot.Bird) -> some View {
        VStack(spacing: 0) {
            PuffMascot(bird, pose: .happy, size: 360)
            HStack(spacing: 0) {
                PuffMascot(bird, pose: .wave, size: 130)
                PuffMascot(bird, pose: .celebrate, size: 130)
                PuffMascot(bird, pose: .thinking, size: 130)
            }
            HStack(spacing: 0) {
                PuffMascot(bird, pose: .curious, size: 130)
                PuffMascot(bird, pose: .sleepy, size: 130)
                PuffMascot(bird, pose: .pout, size: 130)
            }
        }
    }
}
#endif
