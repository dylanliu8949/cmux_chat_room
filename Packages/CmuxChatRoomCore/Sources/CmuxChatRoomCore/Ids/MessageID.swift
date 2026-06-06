public import Foundation

/// Identifier for a single reply message.
public struct MessageID: Hashable, Sendable, Codable {
    /// The underlying value.
    public let raw: UUID
    /// Creates an identifier wrapping `raw`.
    public init(raw: UUID) { self.raw = raw }
}
