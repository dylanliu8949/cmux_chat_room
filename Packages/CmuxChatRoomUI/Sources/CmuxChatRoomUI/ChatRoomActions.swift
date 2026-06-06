public import CmuxChatRoomCore

/// Side-effect closures the host app provides to ``ChatRoomView`` (kept out of the coordinator so the
/// UI package never imports AppKit/cmux). All are `@MainActor`.
@MainActor
public struct ChatRoomActions {
    /// Select/reveal the agent's tab in the sidebar (the "go to source" link).
    public var goToAgent: (AgentID) -> Void
    /// Copy raw text to the clipboard.
    public var copyText: (String) -> Void

    /// Creates an actions bundle.
    public init(goToAgent: @escaping (AgentID) -> Void, copyText: @escaping (String) -> Void) {
        self.goToAgent = goToAgent
        self.copyText = copyText
    }
}
