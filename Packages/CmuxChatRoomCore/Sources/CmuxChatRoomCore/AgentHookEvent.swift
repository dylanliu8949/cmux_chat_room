/// A normalized agent hook event the app-side bridge hands to ``AgentTurnEvent/from(hook:)``.
///
/// The bridge resolves the agent (workspace + role check) and extracts the final message from the
/// raw payload; this value carries only what the routing decision needs, so the decision itself is
/// pure and unit-testable without AppKit, sockets, or a live `WorkstreamEvent`.
public struct AgentHookEvent: Sendable {
    /// The normalized hook kind.
    public let kind: AgentHookKind
    /// The agent the hook came from (one agent per tab in v1, so this is the tab/workspace id).
    public let agent: AgentID
    /// The agent's final message, present only for a ``AgentHookKind/stop`` that carried one.
    public let finalMessage: String?

    /// Creates a normalized hook event.
    public init(kind: AgentHookKind, agent: AgentID, finalMessage: String?) {
        self.kind = kind
        self.agent = agent
        self.finalMessage = finalMessage
    }
}
