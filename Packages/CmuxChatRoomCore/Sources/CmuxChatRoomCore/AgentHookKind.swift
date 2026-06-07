/// The kind of agent hook the app-side bridge received, normalized across agent CLIs.
///
/// Only ``stop`` (the agent's **top-level** turn completion) routes a reply. ``subagentStop`` — a
/// sub-agent finishing inside a turn — is deliberately distinct so it is never mistaken for a turn
/// completion.
public enum AgentHookKind: String, Sendable, Codable {
    /// The agent submitted a prompt (diagnostic signal only).
    case promptSubmit
    /// The agent's top-level turn completed.
    case stop
    /// A sub-agent finished inside the agent's turn — not a turn completion.
    case subagentStop
    /// The agent's session (re)started. Any chat turn bound before this was injected into the
    /// pre-agent shell and is lost, so the coordinator invalidates those stale bindings.
    case sessionStart
    /// Any other hook the chat room does not act on.
    case other
}
