internal import CmuxChatRoomCore

/// One room's in-memory view state: a bounded recent window of exchanges (full set is in the store).
struct RoomChannel {
    /// The room.
    var roomID: ChatRoomID
    /// Windowed exchanges, oldest-first.
    var exchanges: [Exchange]
    /// True once the oldest loaded exchange is the oldest in the store (no more "Load earlier").
    var reachedStart: Bool
}
