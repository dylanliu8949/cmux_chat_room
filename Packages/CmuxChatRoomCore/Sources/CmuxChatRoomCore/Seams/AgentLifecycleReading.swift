import Foundation

/// Read seam over the existing `Workspace.agentLifecycleStatesByPanelId`. The coordinator reads
/// needs-input state here; it keeps no lifecycle dictionary of its own.
public protocol AgentLifecycleReading: Sendable {
    /// Current state of every known agent.
    func current() async -> [AgentID: AgentLifecycle]
    /// Current state of one agent (`.unknown` if absent).
    func state(of agent: AgentID) async -> AgentLifecycle
    /// Emits each lifecycle transition.
    var changes: AsyncStream<AgentLifecycleChange> { get }
}
