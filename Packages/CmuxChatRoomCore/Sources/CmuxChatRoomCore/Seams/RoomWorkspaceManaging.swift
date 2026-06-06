/// Mutation seam: room CRUD + agent membership, performed on app-owned workspaces.
public protocol RoomWorkspaceManaging: Sendable {
    /// Creates a `.chatRoom` workspace with a fresh stable `chatRoomID`; returns it.
    func createRoom(name: String) async -> ChatRoomID
    /// Renames the room's backing workspace.
    func renameRoom(_ id: ChatRoomID, to name: String) async
    /// Runs the close-room flow. Returns `false` if refused (keep ≥1 room).
    func requestCloseRoom(_ id: ChatRoomID) async -> Bool
    /// Moves an agent to another room by rewriting its `roomID`.
    func setRoom(of agent: AgentID, to room: ChatRoomID) async
}
