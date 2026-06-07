internal import CmuxChatRoomCore

/// A chat-origin turn bound to an agent at **inject time** and awaiting that agent's next
/// `turnCompleted`. The coordinator keeps a per-agent FIFO of these; the agent's next completion
/// pops the front and routes its final message to `exchangeID` in `roomID`.
struct ChatTurn {
    let exchangeID: ExchangeID
    let roomID: ChatRoomID
    let agent: AgentID
}
