import Foundation

/// Read seam: the rooms and the active room, **derived** from the live `.chatRoom` workspaces.
///
/// The coordinator owns no `rooms` array or `activeRoom` flag — it reads them here so there is a
/// single source of truth.
public protocol RoomWorkspaceReading: Sendable {
    /// All rooms, from live `.chatRoom` workspaces (each `id` == its persisted `chatRoomID`).
    func rooms() async -> [ChatRoom]
    /// The active room: selected `.chatRoom` → its `chatRoomID`; selected `.agent` → that agent's
    /// `roomID`; nothing selected → `nil`.
    func activeRoomID() async -> ChatRoomID?
    /// Emits when the room list or selection changes.
    var changes: AsyncStream<Void> { get }
}
