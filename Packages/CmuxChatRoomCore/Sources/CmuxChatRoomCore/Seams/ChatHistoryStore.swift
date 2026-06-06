/// Repository seam: persist exchanges per room, keyed by the stable ``ChatRoomID``. Supports paged
/// reads for "Load earlier". The concrete `JSONChatHistoryStore` lives in `CmuxChatRoom`.
public protocol ChatHistoryStore: Sendable {
    /// Append a new exchange to `room`.
    func append(_ exchange: Exchange, in room: ChatRoomID) async
    /// Replace an existing exchange (same `exchangeID`) in `room`.
    func update(_ exchange: Exchange, in room: ChatRoomID) async
    /// The most recent `limit` exchanges in `room`, oldest-first.
    func recent(in room: ChatRoomID, limit: Int) async -> [Exchange]
    /// Up to `limit` exchanges immediately older than `before`, oldest-first.
    func page(in room: ChatRoomID, before: ExchangeID, limit: Int) async -> [Exchange]
}
