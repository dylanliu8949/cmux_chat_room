import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

@MainActor
@Suite struct MoveAndCloseTests {
    @Test func inFlightReplyLandsInOriginatingRoomAfterMove() async {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let roomA = ChatRoomID(raw: UUID()); let roomB = ChatRoomID(raw: UUID())
        let agent = AgentID(raw: UUID())
        let snap = AgentIdentitySnapshot(agentID: agent, title: "A", kind: .claudeCode, cwdDisplay: "~/a", branch: nil)
        await roster.set([snap], inRoom: roomA)
        await rooms.setActive(roomA)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)

        await coord.send(in: roomA, "from A", to: [AgentMention(agentID: agent)], origin: .userMention)
        let text = await inj.lastText()!
        await coord.move(agent, to: roomB)
        #expect(await rooms.moved.contains(where: { $0.0 == agent && $0.1 == roomB }))

        let surf = SurfaceID(raw: UUID())
        coord.handle(.promptSubmitted(surf, rawPromptText: text))
        coord.handle(.turnCompleted(surf, finalMessage: "reply"))
        #expect((coord.channels[roomA] ?? []).count == 1)
        #expect((coord.channels[roomB] ?? []).isEmpty)
    }

    @Test func tabClosedWithPendingMarksTabClosed() async {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let room = ChatRoomID(raw: UUID()); let agent = AgentID(raw: UUID())
        await roster.set([AgentIdentitySnapshot(agentID: agent, title: "A", kind: .claudeCode, cwdDisplay: "~/a", branch: nil)], inRoom: room)
        await rooms.setActive(room)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)
        await coord.send(in: room, "q", to: [AgentMention(agentID: agent)], origin: .userMention)
        coord.onAgentClosed(agent)
        #expect((coord.channels[room] ?? [])[0].outcomes[agent] == .tabClosed)
    }
}
