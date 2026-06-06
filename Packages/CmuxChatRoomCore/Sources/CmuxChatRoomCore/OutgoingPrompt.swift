public import Foundation

/// One outgoing prompt posted to a room and dispatched to its targets.
public struct OutgoingPrompt: Sendable, Codable {
    /// The exchange this prompt opens.
    public let exchangeID: ExchangeID
    /// The room this exchange lives in.
    public let roomID: ChatRoomID
    /// Why this prompt exists.
    public let origin: PromptOrigin
    /// The user-visible body (clean — never contains the correlation marker).
    /// For a forward this is `"\"<quoted>\"\n<note>"`.
    public let bodyText: String
    /// Targets resolved from **this room's** agents at send time (frozen snapshots).
    public let targets: [AgentIdentitySnapshot]
    /// When sent.
    public let sentAt: Date
    /// Creates an outgoing prompt.
    public init(exchangeID: ExchangeID, roomID: ChatRoomID, origin: PromptOrigin,
                bodyText: String, targets: [AgentIdentitySnapshot], sentAt: Date) {
        self.exchangeID = exchangeID
        self.roomID = roomID
        self.origin = origin
        self.bodyText = bodyText
        self.targets = targets
        self.sentAt = sentAt
    }
}
