/// The status of one target within an ``Exchange``.
public enum ReplyOutcome: Sendable, Codable, Equatable {
    /// Injected (or held) and awaiting the agent's final message.
    case pending
    /// The agent posted its final message.
    case replied(Reply)
    /// The agent's tab closed before replying.
    case tabClosed
    /// The prompt could not be dispatched (target gone, or never left needs-input).
    case failedToDispatch
}
