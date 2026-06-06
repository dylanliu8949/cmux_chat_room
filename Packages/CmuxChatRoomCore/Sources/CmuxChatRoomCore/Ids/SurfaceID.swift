public import Foundation

/// Identifier for an agent's terminal surface (= cmux `panelId`).
public struct SurfaceID: Hashable, Sendable, Codable {
    /// The underlying value.
    public let raw: UUID
    /// Creates an identifier wrapping `raw`.
    public init(raw: UUID) { self.raw = raw }
}
