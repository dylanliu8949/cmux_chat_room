import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

/// Proves both routing directions through the **real** mapper the app uses, so passing here means the
/// coordinator + ``AgentTurnEvent/from(hook:)`` compose correctly — not just isolated units.
@MainActor
@Suite struct EndToEndRoutingTests {
    func fixture(_ agents: [AgentIdentitySnapshot]) async
        -> (RoomsCoordinator, FakeInjector, FakeNotifier, room: ChatRoomID) {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let room = ChatRoomID(raw: UUID())
        await roster.set(agents, inRoom: room)
        await rooms.setActive(room)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)
        return (coord, inj, notif, room)
    }

    func snap(_ id: AgentID, _ title: String, _ kind: AgentKind = .claudeCode) -> AgentIdentitySnapshot {
        AgentIdentitySnapshot(agentID: id, title: title, kind: kind, cwdDisplay: "~/w", branch: "main")
    }

    // MARK: chatroom -> agent tab

    @Test func mentioningAgentsInjectsPlainBodyToEachAgentTab() async {
        let a1 = AgentID(raw: UUID()); let a2 = AgentID(raw: UUID())
        let f = await fixture([snap(a1, "claude code 1"), snap(a2, "codex 1", .codex)])
        await f.0.send(in: f.room, "do the thing", to: [AgentMention(agentID: a1), AgentMention(agentID: a2)],
                       origin: .userMention)

        let injected = await f.1.injected
        #expect(injected.count == 2)
        // No appended marker — the agent receives exactly the user's body.
        #expect(injected.allSatisfy { $0.text == "do the thing" })
        #expect(Set(injected.map(\.agent)) == [a1, a2])
    }

    // MARK: agent tab -> chatroom

    @Test func agentStopHookRoutesReplyToChannel() async {
        let agent = AgentID(raw: UUID())
        let f = await fixture([snap(agent, "claude code 1")])
        await f.0.send(in: f.room, "review this", to: [AgentMention(agentID: agent)], origin: .userMention)

        // Exactly what the app bridge does: build a normalized hook event, map it, hand it to handle().
        let turn = AgentTurnEvent.from(hook: AgentHookEvent(kind: .stop, agent: agent, finalMessage: "LGTM"))
        let unwrapped = try? #require(turn)
        if let unwrapped { f.0.handle(unwrapped) }

        let ex = (f.0.channels[f.room] ?? [])[0]
        if case let .replied(r) = ex.outcomes[agent] { #expect(r.markdownBody == "LGTM") }
        else { Issue.record("expected reply, got \(String(describing: ex.outcomes[agent]))") }
    }

    // Regression guard: a `sessionStart` must NOT invalidate a live binding. Agents (codex) fire
    // `sessionStart` ~2s *after* a prompt is injected into a starting agent that does receive it, so
    // discarding on sessionStart wrongly failed legitimate sends. The binding must survive and route.
    @Test func sessionStartDoesNotDiscardLiveBinding() async {
        let agent = AgentID(raw: UUID())
        let f = await fixture([snap(agent, "codex 1", .codex)])

        await f.0.send(in: f.room, "hello", to: [AgentMention(agentID: agent)], origin: .userMention)
        f.0.handle(.agentSessionStarted(agent))  // fires after inject; must be a no-op for the binding
        f.0.handle(.turnCompleted(agent, finalMessage: "hi back"))

        let ex = (f.0.channels[f.room] ?? [])[0]
        if case let .replied(r) = ex.outcomes[agent] {
            #expect(r.markdownBody == "hi back")
        } else {
            Issue.record("binding should survive sessionStart, got \(String(describing: ex.outcomes[agent]))")
        }
    }

    @Test func subagentStopHookDoesNotRouteReply() async {
        let agent = AgentID(raw: UUID())
        let f = await fixture([snap(agent, "claude code 1")])
        await f.0.send(in: f.room, "big task", to: [AgentMention(agentID: agent)], origin: .userMention)

        // A sub-agent finishing maps to nil, so the bridge calls handle() with nothing — the chat
        // turn stays pending until the agent's *top-level* stop arrives.
        let turn = AgentTurnEvent.from(hook: AgentHookEvent(kind: .subagentStop, agent: agent, finalMessage: "sub done"))
        #expect(turn == nil)

        let ex = (f.0.channels[f.room] ?? [])[0]
        #expect(ex.outcomes[agent] == .pending)
    }
}
