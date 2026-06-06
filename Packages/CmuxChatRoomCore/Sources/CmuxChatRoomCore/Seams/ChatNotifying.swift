/// Write seam: badge a room for a completed chat-origin turn when that room isn't active.
/// Needs-input notification targets the agent tab and is lifecycle-driven in the app, not here.
public protocol ChatNotifying: Sendable {
    /// Badge `room` for a new completion.
    func notifyRoomCompletion(_ room: ChatRoomID) async
}
