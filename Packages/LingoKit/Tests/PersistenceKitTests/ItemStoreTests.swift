import Foundation
import Testing
@testable import PersistenceKit

@Suite("ItemStore")
struct ItemStoreTests {
    private func makeStore() throws -> ItemStore {
        ItemStore(modelContainer: try ModelContainerFactory.makeContainer(inMemory: true))
    }

    @Test("发放与查询机票")
    func addAndQuery() async throws {
        let store = try makeStore()
        #expect(try await store.hasTicket(source: .story) == false)
        _ = try await store.addTicket(type: .ticketUniversal, source: .story)
        #expect(try await store.hasTicket(source: .story))
        let tickets = try await store.unconsumedTickets()
        #expect(tickets.count == 1)
        #expect(tickets.first?.type == .ticketUniversal)
    }

    @Test("消耗机票后不再出现在未使用列表，重复消耗抛错")
    func consume() async throws {
        let store = try makeStore()
        let ticket = try await store.addTicket(type: .ticketCountry, countryCode: "GB", source: .purchase)
        try await store.consume(itemID: ticket.id)
        #expect(try await store.unconsumedTickets().isEmpty)
        await #expect(throws: ItemStore.ItemError.alreadyConsumed) {
            try await store.consume(itemID: ticket.id)
        }
    }
}
