/// Chat-room-space mirror of the app's agent lifecycle, exposed by ``AgentLifecycleReading``.
public enum AgentLifecycle: String, Sendable, Codable {
    /// State not yet known.
    case unknown
    /// The agent is actively working a turn.
    case running
    /// The agent is idle and ready for input.
    case idle
    /// The agent is blocked on a permission/confirmation prompt; raw injection is unsafe.
    case needsInput
}
