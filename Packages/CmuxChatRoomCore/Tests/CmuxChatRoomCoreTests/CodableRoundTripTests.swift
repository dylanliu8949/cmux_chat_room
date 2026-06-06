import Foundation
import Testing
@testable import CmuxChatRoomCore

@Suite struct CodableRoundTripTests {
    @Test func agentIDEncodesAndDecodes() throws {
        let id = AgentID(raw: UUID())
        let data = try JSONEncoder().encode(id)
        let back = try JSONDecoder().decode(AgentID.self, from: data)
        #expect(back == id)
    }

    @Test func chatRoomIDIsValueEqual() {
        let u = UUID()
        #expect(ChatRoomID(raw: u) == ChatRoomID(raw: u))
        #expect(ChatRoomID(raw: u) != ChatRoomID(raw: UUID()))
    }

    @Test func agentKindRawValuesAreStable() {
        #expect(AgentKind.claudeCode.rawValue == "claudeCode")
        #expect(AgentKind.codex.rawValue == "codex")
        #expect(AgentKind.cursor.rawValue == "cursor")
        #expect(AgentKind.allCases.count == 3)
    }

    @Test func agentLifecycleDecodesFromRaw() throws {
        let data = Data(#""needsInput""#.utf8)
        #expect(try JSONDecoder().decode(AgentLifecycle.self, from: data) == .needsInput)
    }

    @Test func exchangeWithRepliedOutcomeRoundTrips() throws {
        let agent = AgentID(raw: UUID())
        let snap = AgentIdentitySnapshot(agentID: agent, title: "claude code 1",
                                         kind: .claudeCode, cwdDisplay: "~/work/cmux", branch: "main")
        let ex = ExchangeID(raw: UUID())
        let prompt = OutgoingPrompt(exchangeID: ex, roomID: ChatRoomID(raw: UUID()),
                                    origin: .userMention, bodyText: "review this",
                                    targets: [snap], sentAt: Date(timeIntervalSince1970: 100))
        let reply = Reply(id: MessageID(raw: UUID()), exchangeID: ex, from: snap,
                          markdownBody: "Done.\n\n- fixed x", receivedAt: Date(timeIntervalSince1970: 200))
        let exchange = Exchange(prompt: prompt, outcomes: [agent: .replied(reply)])

        let data = try JSONEncoder().encode(exchange)
        let back = try JSONDecoder().decode(Exchange.self, from: data)
        #expect(back.id == ex)
        #expect(back.outcomes[agent] == .replied(reply))
        #expect(back.prompt.targets.first?.title == "claude code 1")
    }
}
