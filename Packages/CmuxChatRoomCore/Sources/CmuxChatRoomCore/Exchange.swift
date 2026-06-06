/// One outgoing prompt plus the per-target outcomes (one level deep — no nested threads).
public struct Exchange: Sendable, Codable, Identifiable {
    /// Stable id (== `prompt.exchangeID`).
    public var id: ExchangeID { prompt.exchangeID }
    /// The prompt that opened this exchange.
    public let prompt: OutgoingPrompt
    /// Per-target outcome, keyed by ``AgentID``.
    public var outcomes: [AgentID: ReplyOutcome]
    /// Creates an exchange.
    public init(prompt: OutgoingPrompt, outcomes: [AgentID: ReplyOutcome]) {
        self.prompt = prompt
        self.outcomes = outcomes
    }
}
