internal import CmuxChatRoomCore

/// A chat prompt held back because its target was `needsInput` at send time. When the agent leaves
/// `needsInput` the coordinator injects `body` and binds the resulting ``ChatTurn``.
struct HeldPrompt {
    let exchangeID: ExchangeID
    let roomID: ChatRoomID
    let agent: AgentID
    let body: String
}
