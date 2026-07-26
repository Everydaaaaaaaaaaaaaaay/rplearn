import DesignSystem
import SwiftUI
import UIKit

/// 语音升级引导弹窗：检测到仅有机械音时提示用户下载 Apple 增强/高级语音。
/// 说明：第三方 App 无法直接下载系统语音，只能引导到「设置 › 辅助功能 › 朗读内容 › 声音」。
public struct VoiceUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let onPreview: () -> Void
    private let onNeverRemind: () -> Void

    public init(onPreview: @escaping () -> Void, onNeverRemind: @escaping () -> Void) {
        self.onPreview = onPreview
        self.onNeverRemind = onNeverRemind
    }

    private struct Step: Identifiable {
        let id: Int
        let text: String
    }

    private let steps: [Step] = [
        .init(id: 1, text: "打开「系统设置 › 辅助功能」"),
        .init(id: 2, text: "进入「朗读内容 › 声音 › 英语」"),
        .init(id: 3, text: "下载带「增强」或「高级」标记的语音"),
        .init(id: 4, text: "回到本 App，新语音自动生效"),
    ]

    private let recommended = ["Ava", "Zoe", "Samantha", "Serena", "Daniel", "Matilda"]

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    stepsList
                    recommendedList
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle("让语音更自然")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("稍后") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.dsSky)
            Text("现在的语音是系统自带的「标准」音，听起来偏机械。")
                .font(.headline)
            Text("花 1 分钟下载 Apple 的「增强 / 高级」语音，角色台词和单词发音都会明显更自然、更像真人——完全免费、离线可用。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(step.id)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.dsSky, in: Circle())
                    Text(step.text)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var recommendedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("推荐下载")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowChips(items: recommended)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text("打开系统设置")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.dsActionPrimary)

            HStack {
                Button {
                    onPreview()
                } label: {
                    Label("试听当前语音", systemImage: "play.circle")
                }
                Spacer()
                Button("不再提醒", role: .destructive) {
                    onNeverRemind()
                    dismiss()
                }
            }
            .font(.subheadline)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

/// 轻量标签流式布局（推荐语音名）。
private struct FlowChips: View {
    let items: [String]

    var body: some View {
        // 数量少，两行即可容纳，用自适应网格避免手写换行。
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { name in
                DSChip(name, tint: .dsSky)
            }
        }
    }
}
