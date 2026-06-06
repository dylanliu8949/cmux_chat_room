import Foundation
import CmuxChatRoomCore

/// Fake implementing both room seams. Tests set `roomsValue`/`activeValue` and read the call records.
actor FakeRoomWorkspace: RoomWorkspaceReading, RoomWorkspaceManaging {
    var roomsValue: [ChatRoom] = []
    var activeValue: ChatRoomID?
    private(set) var created: [String] = []
    private(set) var renamed: [(ChatRoomID, String)] = []
    private(set) var closeRequested: [ChatRoomID] = []
    private(set) var moved: [(AgentID, ChatRoomID)] = []
    var closeResult = true

    private let stream: AsyncStream<Void>
    private let cont: AsyncStream<Void>.Continuation
    init() { (stream, cont) = AsyncStream<Void>.makeStream() }
    nonisolated var changes: AsyncStream<Void> { stream }
    func emitChange() { cont.yield(()) }

    func setRooms(_ r: [ChatRoom]) { roomsValue = r }
    func setActive(_ id: ChatRoomID?) { activeValue = id }

    func rooms() async -> [ChatRoom] { roomsValue }
    func activeRoomID() async -> ChatRoomID? { activeValue }

    func createRoom(name: String) async -> ChatRoomID {
        created.append(name)
        let id = ChatRoomID(raw: UUID())
        roomsValue.append(ChatRoom(id: id, name: name))
        return id
    }
    func renameRoom(_ id: ChatRoomID, to name: String) async { renamed.append((id, name)) }
    func requestCloseRoom(_ id: ChatRoomID) async -> Bool { closeRequested.append(id); return closeResult }
    func setRoom(of agent: AgentID, to room: ChatRoomID) async { moved.append((agent, room)) }
}
