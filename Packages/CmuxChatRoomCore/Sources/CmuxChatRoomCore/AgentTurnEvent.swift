/// Normalized turn events the coordinator consumes (sourced from the existing hook pipeline by the
/// app-side bridge).
///
/// Correlation is **inject-time**: the coordinator binds an exchange to an agent the moment it
/// injects a prompt, then pairs the agent's next ``turnCompleted`` (FIFO) to that exchange. Events
/// are therefore keyed by ``AgentID`` (one agent per tab in v1), and no marker travels in the prompt.
public enum AgentTurnEvent: Sendable {
    /// `agent` submitted a prompt. Diagnostic only — a signal that an injected prompt reached the
    /// agent and was submitted. Not used for correlation (binding happens at inject time).
    case promptSubmitted(AgentID)
    /// `agent`'s **top-level** turn completed, carrying its final message (`last_assistant_message`).
    /// Sub-agent completions (`subagentStop`) are not turn completions and must not be mapped here.
    case turnCompleted(AgentID, finalMessage: String)
    /// `agent`'s session (re)started — any chat turn bound before this point was injected into the
    /// pre-agent shell and never reached the agent, so the coordinator discards those bindings.
    case agentSessionStarted(AgentID)
}

public extension AgentTurnEvent {
    /// Maps a normalized agent hook event to a turn event, or `nil` if the hook should be ignored.
    ///
    /// The routing rules, in one place: a top-level ``AgentHookKind/stop`` carrying a non-empty final
    /// message becomes a ``turnCompleted``; a prompt submit becomes a ``promptSubmitted`` (diagnostic);
    /// ``AgentHookKind/subagentStop`` and everything else are ignored — a sub-agent finishing is **not**
    /// the agent's turn completing.
    static func from(hook: AgentHookEvent) -> AgentTurnEvent? {
        switch hook.kind {
        case .promptSubmit:
            return .promptSubmitted(hook.agent)
        case .stop:
            guard let final = hook.finalMessage, !final.isEmpty else { return nil }
            return .turnCompleted(hook.agent, finalMessage: final)
        case .sessionStart:
            return .agentSessionStarted(hook.agent)
        case .subagentStop, .other:
            return nil
        }
    }
}
