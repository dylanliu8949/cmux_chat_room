import Foundation
import Testing
@testable import CmuxChatRoomCore

/// The agent-tab → chatroom direction at the bridge seam: a normalized agent hook event maps to the
/// correct ``AgentTurnEvent`` (or is ignored). These are exactly the rules whose violations broke
/// reply routing in the field (sub-agent stops treated as completions, empty final messages).
@Suite struct AgentTurnEventMappingTests {
    let agent = AgentID(raw: UUID())

    @Test func topLevelStopWithFinalMessageBecomesTurnCompleted() {
        let event = AgentTurnEvent.from(
            hook: AgentHookEvent(kind: .stop, agent: agent, finalMessage: "the reply"))
        guard case let .turnCompleted(a, finalMessage) = event else {
            Issue.record("expected .turnCompleted, got \(String(describing: event))"); return
        }
        #expect(a == agent)
        #expect(finalMessage == "the reply")
    }

    @Test func subagentStopIsNotATurnCompletion() {
        // A sub-agent finishing inside the turn must NOT route a reply (this was the bug that popped
        // the wrong binding and dropped the real top-level reply).
        let event = AgentTurnEvent.from(
            hook: AgentHookEvent(kind: .subagentStop, agent: agent, finalMessage: "subagent output"))
        #expect(event == nil)
    }

    @Test func stopWithoutFinalMessageIsIgnored() {
        #expect(AgentTurnEvent.from(hook: AgentHookEvent(kind: .stop, agent: agent, finalMessage: nil)) == nil)
        #expect(AgentTurnEvent.from(hook: AgentHookEvent(kind: .stop, agent: agent, finalMessage: "")) == nil)
    }

    @Test func promptSubmitBecomesPromptSubmitted() {
        let event = AgentTurnEvent.from(
            hook: AgentHookEvent(kind: .promptSubmit, agent: agent, finalMessage: nil))
        guard case let .promptSubmitted(a) = event else {
            Issue.record("expected .promptSubmitted, got \(String(describing: event))"); return
        }
        #expect(a == agent)
    }

    @Test func unrelatedHooksAreIgnored() {
        #expect(AgentTurnEvent.from(hook: AgentHookEvent(kind: .other, agent: agent, finalMessage: "x")) == nil)
    }

    @Test func sessionStartBecomesAgentSessionStarted() {
        let event = AgentTurnEvent.from(hook: AgentHookEvent(kind: .sessionStart, agent: agent, finalMessage: nil))
        guard case let .agentSessionStarted(a) = event else {
            Issue.record("expected .agentSessionStarted, got \(String(describing: event))"); return
        }
        #expect(a == agent)
    }
}
