internal import CmuxChatRoomCore

/// A chat prompt held back because its target was `needsInput` at send time.
struct HeldPrompt {
    let requestID: ChatRequestID
    let exchangeID: ExchangeID
    let roomID: ChatRoomID
    let agent: AgentID
    let bodyWithMarker: String
}
