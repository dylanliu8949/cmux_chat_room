/// An agent's display identity **frozen at send time**, stamped onto every prompt target and reply
/// so channel history never mutates when a tab is later renamed or switches branch.
public struct AgentIdentitySnapshot: Sendable, Codable, Hashable {
    /// The agent this snapshot describes.
    public let agentID: AgentID
    /// Editable tab title at send time.
    public let title: String
    /// Which CLI this agent is.
    public let kind: AgentKind
    /// `~`-abbreviated working directory at send time.
    public let cwdDisplay: String
    /// Git branch at send time, if known.
    public let branch: String?
    /// Creates a frozen identity snapshot.
    public init(agentID: AgentID, title: String, kind: AgentKind, cwdDisplay: String, branch: String?) {
        self.agentID = agentID
        self.title = title
        self.kind = kind
        self.cwdDisplay = cwdDisplay
        self.branch = branch
    }
}
