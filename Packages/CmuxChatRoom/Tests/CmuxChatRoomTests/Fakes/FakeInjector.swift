import Foundation
import CmuxChatRoomCore

/// Fake injector recording every injected `(text, agent)`; tests can force a dispatch failure.
actor FakeInjector: PromptInjecting {
    private(set) var injected: [(text: String, agent: AgentID)] = []
    var failFor: Set<AgentID> = []
    func failNext(for agent: AgentID) { failFor.insert(agent) }
    func inject(_ text: String, into agent: AgentID) async -> Bool {
        injected.append((text, agent))
        if failFor.contains(agent) { failFor.remove(agent); return false }
        return true
    }
    func lastText() -> String? { injected.last?.text }
}
