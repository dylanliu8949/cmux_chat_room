/// The coding-agent CLIs supported by the chat room in v1.
public enum AgentKind: String, Sendable, Codable, CaseIterable {
    /// Anthropic Claude Code (via the OMP wrapper).
    case claudeCode
    /// OpenAI Codex CLI.
    case codex
    /// Cursor agent CLI.
    case cursor
}
