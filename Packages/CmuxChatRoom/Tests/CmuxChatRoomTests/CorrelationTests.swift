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

    @Test func chatOriginCompletionRoutesToExchange() async {
        let f = await makeFixture()
        await f.0.send(in: f.room, "review this", to: [AgentMention(agentID: f.agent)], origin: .userMention)

        let injectedText = await f.4.lastText()
        #expect(injectedText != nil)
        let surface = SurfaceID(raw: UUID())
        f.0.handle(.promptSubmitted(surface, rawPromptText: injectedText!))
        f.0.handle(.turnCompleted(surface, finalMessage: "All done."))

        let exchanges = f.0.channels[f.room] ?? []
        #expect(exchanges.count == 1)
        if case let .replied(reply) = exchanges[0].outcomes[f.agent] {
            #expect(reply.markdownBody == "All done.")
            #expect(reply.from.title == "claude code 1")
        } else {
            Issue.record("expected .replied outcome, got \(String(describing: exchanges[0].outcomes[f.agent]))")
        }
    }

    @Test func directTurnWithNoMarkerIsDropped() async {
        let f = await makeFixture()
        let surface = SurfaceID(raw: UUID())
        f.0.handle(.promptSubmitted(surface, rawPromptText: "user typed this directly"))
        f.0.handle(.turnCompleted(surface, finalMessage: "direct result"))
        #expect((f.0.channels[f.room] ?? []).isEmpty)
    }

    @Test func directTurnCompletingFirstWhileChatPendingDoesNotAttach() async {
        let f = await makeFixture()
        await f.0.send(in: f.room, "chat prompt", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        let chatInjected = await f.4.lastText()!
        let surface = SurfaceID(raw: UUID())

        f.0.handle(.promptSubmitted(surface, rawPromptText: chatInjected))
        f.0.handle(.promptSubmitted(surface, rawPromptText: "direct"))
        f.0.handle(.turnCompleted(surface, finalMessage: "chat done"))
        f.0.handle(.turnCompleted(surface, finalMessage: "direct done"))

        let ex = (f.0.channels[f.room] ?? [])[0]
        if case let .replied(r) = ex.outcomes[f.agent] { #expect(r.markdownBody == "chat done") }
        else { Issue.record("chat reply not attached") }
    }

    @Test func byteIdenticalDirectPromptDoesNotBind() async {
        let f = await makeFixture()
        await f.0.send(in: f.room, "do the thing", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        let surface = SurfaceID(raw: UUID())
        f.0.handle(.promptSubmitted(surface, rawPromptText: "do the thing"))
        f.0.handle(.turnCompleted(surface, finalMessage: "leaked?"))

        let ex = (f.0.channels[f.room] ?? [])[0]
        #expect(ex.outcomes[f.agent] == .pending)
    }

    @Test func fifoIsPerSurfaceAcrossTwoAgents() async {
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
        let injected = await inj.injected
        let text1 = injected.first(where: { $0.agent == a1 })!.text
        let text2 = injected.first(where: { $0.agent == a2 })!.text

        let surf1 = SurfaceID(raw: UUID()); let surf2 = SurfaceID(raw: UUID())
        coord.handle(.promptSubmitted(surf1, rawPromptText: text1))
        coord.handle(.promptSubmitted(surf2, rawPromptText: text2))
        coord.handle(.turnCompleted(surf2, finalMessage: "from codex"))
        coord.handle(.turnCompleted(surf1, finalMessage: "from claude"))

        let ex = (coord.channels[room] ?? [])[0]
        if case let .replied(r) = ex.outcomes[a1] { #expect(r.markdownBody == "from claude") } else { Issue.record("a1") }
        if case let .replied(r) = ex.outcomes[a2] { #expect(r.markdownBody == "from codex") } else { Issue.record("a2") }
    }
}
