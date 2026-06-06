public import Foundation

/// Correlation token minted per injected chat prompt.
///
/// Embedded invisibly via ``ChatPromptMarker`` and recovered at `prompt-submit` to bind a turn to
/// its originating exchange.
public struct ChatRequestID: Hashable, Sendable, Codable {
    /// The underlying value.
    public let raw: UUID
    /// Creates an identifier wrapping `raw`.
    public init(raw: UUID) { self.raw = raw }
}
