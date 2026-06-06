/// Write seam: inject raw text into an agent's terminal surface (wraps `surface.send_text` + submit,
/// non-focus-stealing). Returns `false` if the agent could not be reached (→ `.failedToDispatch`).
///
/// Takes an ``AgentID`` (not a ``SurfaceID``): the app owns the agent→surface mapping; the
/// coordinator learns the surface only from ``AgentTurnEvent``s.
public protocol PromptInjecting: Sendable {
    /// Injects `text` into `agent`'s surface and submits it.
    func inject(_ text: String, into agent: AgentID) async -> Bool
}
