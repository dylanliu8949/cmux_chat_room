import Foundation

/// Role of a workspace in the chat-room model.
///
/// Every legacy/terminal workspace is an ``agent``; ``chatRoom`` workspaces back a chat channel and
/// are rendered in the top sidebar section. Persisted via `SessionWorkspaceSnapshot.workspaceRoleRaw`.
enum WorkspaceRole: String, Codable, Sendable, CaseIterable {
    /// An agent terminal tab (the default for all pre-existing workspaces).
    case agent
    /// A chat room channel.
    case chatRoom
}
