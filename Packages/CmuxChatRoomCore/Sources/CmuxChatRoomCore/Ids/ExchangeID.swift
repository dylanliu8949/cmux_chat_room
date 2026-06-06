public import Foundation

/// Identifier for one outgoing prompt plus its replies.
public struct ExchangeID: Hashable, Sendable, Codable {
    /// The underlying value.
    public let raw: UUID
    /// Creates an identifier wrapping `raw`.
    public init(raw: UUID) { self.raw = raw }
}
