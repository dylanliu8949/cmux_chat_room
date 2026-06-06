import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

@MainActor
@Suite struct ForwardQuoteTests {
    func fixture() async -> (RoomsCoordinator, FakeRoster, FakeInjector, room: ChatRoomID, agent: AgentID) {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let room = ChatRoomID(raw: UUID()); let agent = AgentID(raw: UUID())
        await roster.set([AgentIdentitySnapshot(agentID: agent, title: "A", kind: .claudeCode, cwdDisplay: "~/a", branch: "main")], inRoom: room)
        await rooms.setActive(room)
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)
        return (coord, roster, inj, room, agent)
    }

    @Test func forwardWrapsQuoteAndNoteAsNewExchange() async {
        let f = await fixture()
        let src = MessageID(raw: UUID())
        await f.0.forward(src, quoted: "3 issues found", note: "fix #2 first",
                          to: [AgentMention(agentID: f.agent)], in: f.room)
        let ex = (f.0.channels[f.room] ?? [])[0]
        #expect(ex.prompt.bodyText == "\"3 issues found\"\nfix #2 first")
        #expect(ex.prompt.origin == .forward(sourceMessageID: src))
    }

    @Test func targetRemovedBeforeSendCreatesNoExchange() async {
        let f = await fixture()
        let ghost = AgentID(raw: UUID())
        await f.0.send(in: f.room, "hi", to: [AgentMention(agentID: ghost)], origin: .userMention)
        #expect((f.0.channels[f.room] ?? []).isEmpty)
    }

    @Test func injectorFailureMarksFailedToDispatch() async {
        let f = await fixture()
        await f.2.failNext(for: f.agent)
        await f.0.send(in: f.room, "hi", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        #expect((f.0.channels[f.room] ?? [])[0].outcomes[f.agent] == .failedToDispatch)
    }

    @Test func identitySnapshotFrozenAtSendTime() async {
        let f = await fixture()
        await f.0.send(in: f.room, "q", to: [AgentMention(agentID: f.agent)], origin: .userMention)
        await f.1.set([AgentIdentitySnapshot(agentID: f.agent, title: "A", kind: .claudeCode, cwdDisplay: "~/a", branch: "feature")], inRoom: f.room)
        let text = await f.2.lastText()!
        let surf = SurfaceID(raw: UUID())
        f.0.handle(.promptSubmitted(surf, rawPromptText: text))
        f.0.handle(.turnCompleted(surf, finalMessage: "done"))
        if case let .replied(r) = (f.0.channels[f.room] ?? [])[0].outcomes[f.agent] {
            #expect(r.from.branch == "main")
        } else { Issue.record("no reply") }
    }
}
