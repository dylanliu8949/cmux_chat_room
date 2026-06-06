public import Foundation

/// One agent's final message returned to a channel.
public struct Reply: Sendable, Codable, Equatable {
    /// Stable id of this message.
    public let id: MessageID
    /// The exchange this reply belongs to.
    public let exchangeID: ExchangeID
    /// Frozen identity of the replying agent.
    public let from: AgentIdentitySnapshot
    /// The verbatim `last_assistant_message` (markdown).
    public let markdownBody: String
    /// When the reply was received.
    public let receivedAt: Date
    /// Creates a reply.
    public init(id: MessageID, exchangeID: ExchangeID, from: AgentIdentitySnapshot,
                markdownBody: String, receivedAt: Date) {
        self.id = id
        self.exchangeID = exchangeID
        self.from = from
        self.markdownBody = markdownBody
        self.receivedAt = receivedAt
    }
}
