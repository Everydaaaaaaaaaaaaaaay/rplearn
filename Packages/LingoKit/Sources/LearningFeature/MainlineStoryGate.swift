import BackendKit
import DesignSystem
import DomainKit
import SwiftUI

/// 所有主线入口经过此处；服务端状态读取失败时不播放尚未验证的章节。
public struct MainlineStoryGate<Content: View>: View {
    private let storyID: String
    private let service: any MainlineServing
    private let content: () -> Content
    @State private var chapter: BackendMainlineProgress.Chapter?
    @State private var error: String?
    @State private var isLoading = true
    public init(storyID: String, service: any MainlineServing, @ViewBuilder content: @escaping () -> Content) {
        self.storyID = storyID; self.service = service; self.content = content
    }
    public var body: some View {
        Group {
            if chapter?.canOpen == true { content() }
            else if isLoading { ProgressView("正在确认旅程进度…") }
            else {
                ContentUnavailableView {
                    Label(error == nil ? "故事在前方等你" : "暂时无法打开剧情", systemImage: error == nil ? "lock.open.rotation" : "wifi.exclamationmark")
                } description: {
                    Text(error ?? chapter?.statusText ?? "暂时无法确认这一章的状态。")
                    if let chapter, error == nil { Text("需要累计 \(chapter.requiredStars) 颗星，并完成前一章。请回到角色学习页继续挑战。") }
                } actions: { Button("刷新进度") { Task { await load() } } }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.dsBackground)
            .task { await load() }
    }
    private func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            let status = try await service.mainlineProgress()
            chapter = status.chapters.first { $0.storyId == DepartureStoryIdentity.rewardID(for: storyID) }
            error = chapter == nil ? "没有找到这一章的进度，请更新后重试。" : nil
        } catch { self.error = "请联网后重试，已获得的星星不会丢失。" }
    }
}
