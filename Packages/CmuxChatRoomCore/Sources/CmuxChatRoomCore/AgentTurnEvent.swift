/// Normalized turn events the coordinator consumes (sourced from the existing hook pipeline by the
/// app-side bridge). Carries ``SurfaceID`` so per-surface FIFO works when a workspace holds multiple
/// agent panels.
public enum AgentTurnEvent: Sendable {
    /// A prompt was submitted on `surface`. `rawPromptText` is the **un-normalized** prompt
    /// (from `toolInputJSON`, not the whitespace-collapsed `submittedPromptMessage`) so the embedded
    /// ``ChatPromptMarker`` survives and is extractable.
    case promptSubmitted(SurfaceID, rawPromptText: String)
    /// A turn completed on `surface`, carrying the agent's final message (`last_assistant_message`).
    case turnCompleted(SurfaceID, finalMessage: String)
}
