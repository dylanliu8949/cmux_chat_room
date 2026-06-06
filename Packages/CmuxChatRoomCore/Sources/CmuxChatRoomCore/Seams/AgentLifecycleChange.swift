/// A single lifecycle transition, yielded by ``AgentLifecycleReading/changes``.
public struct AgentLifecycleChange: Sendable, Equatable {
    /// The agent whose state changed.
    public let agent: AgentID
    /// The new state.
    public let state: AgentLifecycle
    /// Creates a change.
    public init(agent: AgentID, state: AgentLifecycle) {
        self.agent = agent
        self.state = state
    }
}
