import Foundation
import CmuxChatRoomCore

/// Fake roster. Tests set `byRoom` to control who is mentionable per room.
actor FakeRoster: AgentRosterProviding {
    var byRoom: [ChatRoomID: [AgentIdentitySnapshot]] = [:]
    private let stream: AsyncStream<Void>
    private let cont: AsyncStream<Void>.Continuation
    init() { (stream, cont) = AsyncStream<Void>.makeStream() }
    nonisolated var changes: AsyncStream<Void> { stream }

    func set(_ snaps: [AgentIdentitySnapshot], inRoom room: ChatRoomID) { byRoom[room] = snaps }
    func current(inRoom room: ChatRoomID) async -> [AgentIdentitySnapshot] { byRoom[room] ?? [] }
}
