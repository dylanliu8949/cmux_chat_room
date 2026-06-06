internal import CmuxChatRoomCore

/// One entry in a surface's FIFO turn queue. `stop` events carry no marker, so the queue (filled at
/// `prompt-submit`, popped at `stop`) is what pairs a completion with its originating exchange.
enum TurnBinding {
    /// A chat-origin turn bound via the marker.
    case chatOrigin(request: ChatRequestID, exchange: ExchangeID, room: ChatRoomID, agent: AgentID)
    /// A direct (user-typed-in-tab) turn — its completion is dropped.
    case direct
}
