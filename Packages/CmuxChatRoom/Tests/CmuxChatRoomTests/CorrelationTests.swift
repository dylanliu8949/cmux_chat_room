import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

@MainActor
@Suite struct CorrelationTests {
    func makeFixture() async -> (RoomsCoordinator, FakeRoomWorkspace, FakeRoster, FakeLifecycle,
                                 FakeInjector, FakeNotifier, InMemoryHistoryStore,
                                 room: ChatRoomID, agent: AgentID, snap: AgentIdentitySnapshot) {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let room = ChatRoomID(raw: UUID()); let agent = AgentID(raw: UUID())
        let snap = AgentIdentitySnapshot(agentID: agent, title: "claude code 1",
                                         kind: .claudeCode, cwdDisplay: "~/work/cmux", branch: "main")
        await roster.set([snap], inRoom: room)
        await rooms.setActive(room)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)
        return (coord, rooms, roster, life, inj, notif, hist, room, agent, snap)
    }

    @Test func completionRoutesToExchangeBoundAtSend() async {
        let f = await makeFixture()
        await f.0.send(in: f.room, "review this", to: [AgentMention(agentID: f.agent)], origin: .userMention)

        // No marker in the injected prompt — correlation was bound at inject time.
        let injectedText = await f.4.lastText()
        #expect(injectedText == "review this")

        f.0.handle(.turnCompleted(f.agent, finalMessage: "All done."))

        let exchanges = f.0.channels[f.room] ?? []
        #expect(exchanges.count == 1)
        if case let .replied(reply) = exchanges[0].outcomes[f.agent] {
            #expect(reply.markdownBody == "All done.")
            #expect(reply.from.title == "claude code 1")
        } else {
            Issue.record("expected .replied outcome, got \(String(describing: exchanges[0].outcomes[f.agent]))")
        }
    }

    @Test func completionWithNoPendingChatTurnIsDropped() async {
        let f = await makeFixture()
        // The agent completes a turn the user drove directly in its tab — nothing was bound, so it is
        // treated as a direct turn and dropped (no exchange even exists).
        f.0.handle(.turnCompleted(f.agent, finalMessage: "direct result"))
        #expect((f.0.channels[f.room] ?? []).isEmpty)
    }

    @Test func secondCompletionAfterSinglePendingIsDropped() async {
        let f = await makeFixture()
        await f.0.send(in: f.room, "chat prompt", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        f.0.handle(.turnCompleted(f.agent, finalMessage: "chat reply"))
        // A subsequent completion with an empty queue (e.g. a direct turn) does not attach anywhere.
        f.0.handle(.turnCompleted(f.agent, finalMessage: "later direct turn"))

        let ex = (f.0.channels[f.room] ?? [])[0]
        if case let .replied(r) = ex.outcomes[f.agent] { #expect(r.markdownBody == "chat reply") }
        else { Issue.record("chat reply not attached") }
    }

    @Test func fifoPerAgentPopsInSendOrder() async {
        let f = await makeFixture()
        await f.0.send(in: f.room, "first", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        await f.0.send(in: f.room, "second", to: [AgentMention(agentID: f.agent)], origin: .userMention)

        f.0.handle(.turnCompleted(f.agent, finalMessage: "reply to first"))
        f.0.handle(.turnCompleted(f.agent, finalMessage: "reply to second"))

        let exchanges = f.0.channels[f.room] ?? []
        #expect(exchanges.count == 2)
        if case let .replied(r) = exchanges[0].outcomes[f.agent] { #expect(r.markdownBody == "reply to first") }
        else { Issue.record("first") }
        if case let .replied(r) = exchanges[1].outcomes[f.agent] { #expect(r.markdownBody == "reply to second") }
        else { Issue.record("second") }
    }

    @Test func completionsRouteToOwningAgent() async {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let room = ChatRoomID(raw: UUID())
        let a1 = AgentID(raw: UUID()); let a2 = AgentID(raw: UUID())
        let s1 = AgentIdentitySnapshot(agentID: a1, title: "claude code 1", kind: .claudeCode, cwdDisplay: "~/a", branch: nil)
        let s2 = AgentIdentitySnapshot(agentID: a2, title: "codex 1", kind: .codex, cwdDisplay: "~/b", branch: nil)
        await roster.set([s1, s2], inRoom: room); await rooms.setActive(room)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)

        await coord.send(in: room, "q", to: [AgentMention(agentID: a1), AgentMention(agentID: a2)], origin: .userMention)
        // Completions arrive out of order; each agent's queue is independent.
        coord.handle(.turnCompleted(a2, finalMessage: "from codex"))
        coord.handle(.turnCompleted(a1, finalMessage: "from claude"))

        let ex = (coord.channels[room] ?? [])[0]
        if case let .replied(r) = ex.outcomes[a1] { #expect(r.markdownBody == "from claude") } else { Issue.record("a1") }
        if case let .replied(r) = ex.outcomes[a2] { #expect(r.markdownBody == "from codex") } else { Issue.record("a2") }
    }
}
