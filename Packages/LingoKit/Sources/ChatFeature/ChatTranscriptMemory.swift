import Foundation
import PersistenceKit

/// 进入聊天时第一帧就有消息：在内存里留着最近打开或预取过的会话消息。
///
/// 消息原本在进入后才从数据库异步读取，推入动画的前 0.3 秒聊天区是空白，随后整屏消息一下子出现。
/// 这里按“账号的消息库 + 角色”保存可见消息，聊天页初始化时同步取出；随后照常从数据库刷新，内容一致时不重绘。
/// 只在主线程读写，最多保留 12 个会话。条目弱引用所属消息库并核对身份：换账号后旧库释放，
/// 即使新库恰好落在同一内存地址也不会命中，不会串号。
@MainActor
enum ChatTranscriptMemory {
    private struct Key: Hashable {
        let store: ObjectIdentifier
        let characterID: UUID
    }

    private struct Entry {
        weak var store: ChatStore?
        let messages: [MessageDTO]
    }

    private static var entries: [Key: Entry] = [:]
    private static var order: [Key] = []
    private static let capacity = 12

    static func messages(store: ChatStore, characterID: UUID) -> [MessageDTO]? {
        guard let entry = entries[Key(store: ObjectIdentifier(store), characterID: characterID)],
              entry.store === store else { return nil }
        return entry.messages
    }

    static func remember(_ messages: [MessageDTO], store: ChatStore, characterID: UUID) {
        let key = Key(store: ObjectIdentifier(store), characterID: characterID)
        entries[key] = Entry(store: store, messages: messages)
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            entries[order.removeFirst()] = nil
        }
    }
}
