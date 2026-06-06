/// A named channel, backed by a `.chatRoom` workspace whose stable persisted `chatRoomID` equals
/// ``id`` (NOT the re-minted `Workspace.id`). Membership is the set of agents whose `roomID == id`.
public struct ChatRoom: Sendable, Codable, Identifiable, Equatable {
    /// Stable room identity.
    public let id: ChatRoomID
    /// Renameable display name.
    public var name: String
    /// Creates a room.
    public init(id: ChatRoomID, name: String) {
        self.id = id
        self.name = name
    }
}
