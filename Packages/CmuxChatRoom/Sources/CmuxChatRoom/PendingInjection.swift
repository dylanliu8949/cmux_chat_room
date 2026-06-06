internal import CmuxChatRoomCore

/// A chat prompt that has been injected and is awaiting `prompt-submit`/`stop`.
struct PendingInjection {
    let requestID: ChatRequestID
    let exchangeID: ExchangeID
    let roomID: ChatRoomID
    let agent: AgentID
}
