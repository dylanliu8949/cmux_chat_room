public import Foundation

/// **Stable, persisted** identifier for a chat room.
///
/// Distinct from any `Workspace.id` (which is re-minted on restore); room history and agents'
/// `roomID` key off this so room identity survives restart.
public struct ChatRoomID: Hashable, Sendable, Codable {
    /// The underlying value.
    public let raw: UUID
    /// Creates an identifier wrapping `raw`.
    public init(raw: UUID) { self.raw = raw }
}
