import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

@MainActor
@Suite struct RoomScopingTests {
    @Test func mentionsResolveOnlyToActiveRoomAgents() async {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let roomA = ChatRoomID(raw: UUID()); let roomB = ChatRoomID(raw: UUID())
        let inA = AgentID(raw: UUID()); let inB = AgentID(raw: UUID())
        await roster.set([AgentIdentitySnapshot(agentID: inA, title: "A", kind: .claudeCode, cwdDisplay: "~/a", branch: nil)], inRoom: roomA)
        await roster.set([AgentIdentitySnapshot(agentID: inB, title: "B", kind: .codex, cwdDisplay: "~/b", branch: nil)], inRoom: roomB)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)

        await coord.send(in: roomA, "hi", to: [AgentMention(agentID: inA), AgentMention(agentID: inB)], origin: .userMention)
        let injected = await inj.injected
        #expect(injected.count == 1)
        #expect(injected[0].agent == inA)
        #expect((coord.channels[roomB] ?? []).isEmpty)
    }

    @Test func completionRoutesToOriginatingRoomNotActiveRoom() async {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let roomA = ChatRoomID(raw: UUID()); let roomB = ChatRoomID(raw: UUID())
        let aB = AgentID(raw: UUID())
        await roster.set([AgentIdentitySnapshot(agentID: aB, title: "B", kind: .codex, cwdDisplay: "~/b", branch: nil)], inRoom: roomB)
        await rooms.setActive(roomA)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)

        await coord.send(in: roomB, "for B", to: [AgentMention(agentID: aB)], origin: .userMention)
        coord.handle(.turnCompleted(aB, finalMessage: "B reply"))

        #expect((coord.channels[roomA] ?? []).isEmpty)
        #expect((coord.channels[roomB] ?? []).count == 1)
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(await notif.badged.contains(roomB))
    }
}
