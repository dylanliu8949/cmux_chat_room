import Foundation

/// A user's selection of a single agent to address (from `@`-autocomplete).
///
/// Stores a stable ``AgentID`` — never a display string — so renames/duplicate titles can't
/// misroute. `@all` is expressed by the caller as the full list of a room's mentions.
public struct AgentMention: Hashable, Sendable, Codable {
    /// The addressed agent.
    public let agentID: AgentID
    /// Creates a mention of `agentID`.
    public init(agentID: AgentID) { self.agentID = agentID }
}
