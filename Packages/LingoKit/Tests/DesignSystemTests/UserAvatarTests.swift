import DesignSystem
import Foundation
import Testing
import UIKit

@Suite("User avatar")
@MainActor
struct UserAvatarTests {
    @Test("头像缩小持久化且账号隔离，坏图片保留原头像")
    func persistsAndIsolates() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = UUID()
        let store = UserAvatarStore(accountID: account, directory: directory)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800))
        let photo = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        try await store.save(photoData: #require(photo.pngData()))
        let saved = try #require(store.image)
        #expect(max(saved.size.width, saved.size.height) <= 512)
        #expect(UserAvatarStore(accountID: account, directory: directory).image != nil)
        #expect(UserAvatarStore(accountID: UUID(), directory: directory).image == nil)
        do {
            try await store.save(photoData: Data("invalid".utf8))
            Issue.record("Invalid image unexpectedly accepted")
        } catch {
            #expect(store.image != nil)
            #expect(UserAvatarStore(accountID: account, directory: directory).image != nil)
        }
    }
}
