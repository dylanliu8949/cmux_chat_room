import Foundation
import CmuxChatRoomCore

/// Fake lifecycle store. Tests set states and call `emit` to drive transitions.
actor FakeLifecycle: AgentLifecycleReading {
    var states: [AgentID: AgentLifecycle] = [:]
    private let stream: AsyncStream<AgentLifecycleChange>
    private let cont: AsyncStream<AgentLifecycleChange>.Continuation
    init() { (stream, cont) = AsyncStream<AgentLifecycleChange>.makeStream() }
    nonisolated var changes: AsyncStream<AgentLifecycleChange> { stream }

    func set(_ s: AgentLifecycle, for agent: AgentID) { states[agent] = s }
    func emit(_ s: AgentLifecycle, for agent: AgentID) {
        states[agent] = s
        cont.yield(.init(agent: agent, state: s))
    }
    func current() async -> [AgentID: AgentLifecycle] { states }
    func state(of agent: AgentID) async -> AgentLifecycle { states[agent] ?? .unknown }
}
