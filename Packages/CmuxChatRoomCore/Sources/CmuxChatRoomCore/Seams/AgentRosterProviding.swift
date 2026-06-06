import Foundation

/// Read seam: the mentionable agents in a room (live `.agent` workspaces with `roomID == room` that
/// are chat-supported), as frozen identity snapshots. No parallel registry — `roomID` membership is
/// the source of truth.
public protocol AgentRosterProviding: Sendable {
    /// The room's mentionable agents at call time.
    func current(inRoom room: ChatRoomID) async -> [AgentIdentitySnapshot]
    /// Emits when any room's roster changes.
    var changes: AsyncStream<Void> { get }
}
