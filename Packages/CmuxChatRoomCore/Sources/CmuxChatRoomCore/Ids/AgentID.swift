public import Foundation

/// Stable identifier for an agent tab/workspace. Equals the agent workspace's `id`.
///
/// Re-minted on session restore, so it is **never** used to key persisted history — use
/// ``ChatRoomID`` for durable room identity.
public struct AgentID: Hashable, Sendable, Codable {
    /// The underlying value.
    public let raw: UUID
    /// Creates an identifier wrapping `raw`.
    public init(raw: UUID) { self.raw = raw }
}
