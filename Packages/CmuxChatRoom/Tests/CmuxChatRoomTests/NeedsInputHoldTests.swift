import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

@MainActor
@Suite struct NeedsInputHoldTests {
    func fixture() async -> (RoomsCoordinator, FakeLifecycle, FakeInjector, room: ChatRoomID, agent: AgentID) {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let room = ChatRoomID(raw: UUID()); let agent = AgentID(raw: UUID())
        await roster.set([AgentIdentitySnapshot(agentID: agent, title: "A", kind: .claudeCode, cwdDisplay: "~/a", branch: nil)], inRoom: room)
        await rooms.setActive(room)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)
        return (coord, life, inj, room, agent)
    }

    @Test func sendingToNeedsInputTargetHoldsWithoutInjecting() async {
        let f = await fixture()
        await f.1.set(.needsInput, for: f.agent)
        await f.0.send(in: f.room, "held prompt", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        #expect(await f.2.injected.isEmpty)
        #expect((f.0.channels[f.room] ?? [])[0].outcomes[f.agent] == .pending)
    }

    @Test func leavingNeedsInputFlushesAndInjects() async {
        let f = await fixture()
        await f.1.set(.needsInput, for: f.agent)
        await f.0.send(in: f.room, "held", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        #expect(await f.2.injected.isEmpty)

        await f.0.onLifecycleChange(AgentLifecycleChange(agent: f.agent, state: .idle))
        let injected = await f.2.injected
        #expect(injected.count == 1)
        let (id, _) = ChatPromptMarker.extract(from: injected[0].text)
        #expect(id != nil)
    }

    @Test func heldPromptOnClosedTabResolvesTabClosed() async {
        let f = await fixture()
        await f.1.set(.needsInput, for: f.agent)
        await f.0.send(in: f.room, "held", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        f.0.onAgentClosed(f.agent)
        #expect((f.0.channels[f.room] ?? [])[0].outcomes[f.agent] == .tabClosed)
    }
}
