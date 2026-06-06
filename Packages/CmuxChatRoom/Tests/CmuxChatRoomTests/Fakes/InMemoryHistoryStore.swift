import Foundation
import CmuxChatRoomCore

/// In-memory ``ChatHistoryStore`` for tests; ordered per room, oldest-first.
actor InMemoryHistoryStore: ChatHistoryStore {
    private var byRoom: [ChatRoomID: [Exchange]] = [:]

    func append(_ exchange: Exchange, in room: ChatRoomID) async {
        byRoom[room, default: []].append(exchange)
    }
    func update(_ exchange: Exchange, in room: ChatRoomID) async {
        guard var list = byRoom[room], let i = list.firstIndex(where: { $0.id == exchange.id }) else { return }
        list[i] = exchange
        byRoom[room] = list
    }
    func recent(in room: ChatRoomID, limit: Int) async -> [Exchange] {
        Array((byRoom[room] ?? []).suffix(limit))
    }
    func page(in room: ChatRoomID, before: ExchangeID, limit: Int) async -> [Exchange] {
        let list = byRoom[room] ?? []
        guard let i = list.firstIndex(where: { $0.id == before }) else { return [] }
        return Array(list[..<i].suffix(limit))
    }
}
