/// Why an outgoing prompt exists.
public enum PromptOrigin: Sendable, Codable, Equatable {
    /// The user `@`-mentioned the target(s) directly.
    case userMention
    /// The prompt forwards an earlier reply (the "steering wheel").
    case forward(sourceMessageID: MessageID)
}
