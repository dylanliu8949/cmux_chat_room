import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

@Suite struct JSONChatHistoryStoreTests {
    func tempDir() -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chatroom-hist-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    func exchange(_ body: String, room: ChatRoomID, at t: Double) -> Exchange {
        let p = OutgoingPrompt(exchangeID: ExchangeID(raw: UUID()), roomID: room, origin: .userMention,
                               bodyText: body, targets: [], sentAt: Date(timeIntervalSince1970: t))
        return Exchange(prompt: p, outcomes: [:])
    }

    @Test func appendThenRecentRoundTripsAcrossInstances() async throws {
        let dir = tempDir(); let room = ChatRoomID(raw: UUID())
        let store = JSONChatHistoryStore(directory: dir)
        await store.append(exchange("a", room: room, at: 1), in: room)
        await store.append(exchange("b", room: room, at: 2), in: room)
        let store2 = JSONChatHistoryStore(directory: dir)
        let recent = await store2.recent(in: room, limit: 10)
        #expect(recent.map(\.prompt.bodyText) == ["a", "b"])
    }

    @Test func updateReplacesSameExchange() async {
        let dir = tempDir(); let room = ChatRoomID(raw: UUID())
        let store = JSONChatHistoryStore(directory: dir)
        var ex = exchange("a", room: room, at: 1)
        await store.append(ex, in: room)
        let agent = AgentID(raw: UUID())
        ex.outcomes[agent] = .tabClosed
        await store.update(ex, in: room)
        let recent = await store.recent(in: room, limit: 10)
        #expect(recent.count == 1)
        #expect(recent[0].outcomes[agent] == .tabClosed)
    }

    @Test func pageReturnsOlderBeforeCursor() async {
        let dir = tempDir(); let room = ChatRoomID(raw: UUID())
        let store = JSONChatHistoryStore(directory: dir)
        let exs = (0..<5).map { exchange("m\($0)", room: room, at: Double($0)) }
        for e in exs { await store.append(e, in: room) }
        let page = await store.page(in: room, before: exs[3].id, limit: 2)
        #expect(page.map(\.prompt.bodyText) == ["m1", "m2"])
    }

    @Test func roomsAreIsolatedByID() async {
        let dir = tempDir(); let a = ChatRoomID(raw: UUID()); let b = ChatRoomID(raw: UUID())
        let store = JSONChatHistoryStore(directory: dir)
        await store.append(exchange("inA", room: a, at: 1), in: a)
        #expect(await store.recent(in: b, limit: 10).isEmpty)
        #expect(await store.recent(in: a, limit: 10).map(\.prompt.bodyText) == ["inA"])
    }
}
