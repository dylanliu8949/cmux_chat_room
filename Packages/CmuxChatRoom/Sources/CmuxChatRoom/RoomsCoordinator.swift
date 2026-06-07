public import Foundation
public import CmuxChatRoomCore

/// `@MainActor @Observable` orchestrator for the chat room. Owns channel/correlation/history state
/// only; rooms, roster, and lifecycle are **derived** through read seams.
///
/// Correlation is **inject-time** and room-scoped: when ``send(in:_:to:origin:)`` injects a prompt
/// it binds that exchange to the target agent's per-agent FIFO; the agent's next ``turnCompleted``
/// pops the front and routes its final message to that exchange. Nothing extra is sent in the prompt.
/// A completion from an agent with no queued chat turn is treated as a direct turn and dropped.
@MainActor @Observable
public final class RoomsCoordinator {
    /// Per-room windowed channel state (UI reads this).
    public private(set) var channels: [ChatRoomID: [Exchange]] = [:]

    /// Monotonic counter bumped on every observed lifecycle transition. The UI reads this to know when
    /// to re-fetch ``lifecycleSnapshot()`` — the coordinator keeps **no** lifecycle dictionary of its
    /// own (single source of truth stays the store, spec §4.5; this is only a change signal).
    public private(set) var lifecycleVersion: Int = 0

    private var window: [ChatRoomID: RoomChannel] = [:]
    /// Per-agent FIFO of chat turns bound at **inject time**, each awaiting that agent's next
    /// `turnCompleted`. Replaces the old marker + `prompt-submit` correlation: the marker did not
    /// survive the agents' prompt-submit reporting, so binding now happens when we inject.
    private var turnQueueByAgent: [AgentID: [ChatTurn]] = [:]
    private var heldForNeedsInput: [AgentID: [HeldPrompt]] = [:]

    private let roomsReading: any RoomWorkspaceReading
    private let roomsManaging: any RoomWorkspaceManaging
    private let roster: any AgentRosterProviding
    private let lifecycle: any AgentLifecycleReading
    private let injector: any PromptInjecting
    private let notifier: any ChatNotifying
    private let history: any ChatHistoryStore
    /// Optional diagnostic sink. When `nil` (release default) the coordinator skips building any
    /// diagnostic string. The app wires this to the unified debug log in DEBUG builds so each
    /// correlation decision (bind / pop / unmatched) is observable end-to-end.
    private let diagnostic: ((String) -> Void)?
    private let now: @Sendable () -> Date
    private let makeRequestID: @Sendable () -> ChatRequestID
    private let makeExchangeID: @Sendable () -> ExchangeID
    private let makeMessageID: @Sendable () -> MessageID
    /// Recent-window size for ``loadEarlier(in:)`` paging.
    public let windowSize: Int

    /// Creates a coordinator. All collaborators are injected; the `make*`/`now` closures are
    /// injectable so tests are deterministic.
    public init(
        roomsReading: any RoomWorkspaceReading,
        roomsManaging: any RoomWorkspaceManaging,
        roster: any AgentRosterProviding,
        lifecycle: any AgentLifecycleReading,
        injector: any PromptInjecting,
        notifier: any ChatNotifying,
        history: any ChatHistoryStore,
        windowSize: Int = 50,
        diagnostic: ((String) -> Void)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        makeRequestID: @escaping @Sendable () -> ChatRequestID = { ChatRequestID(raw: UUID()) },
        makeExchangeID: @escaping @Sendable () -> ExchangeID = { ExchangeID(raw: UUID()) },
        makeMessageID: @escaping @Sendable () -> MessageID = { MessageID(raw: UUID()) }
    ) {
        self.roomsReading = roomsReading
        self.roomsManaging = roomsManaging
        self.roster = roster
        self.lifecycle = lifecycle
        self.injector = injector
        self.notifier = notifier
        self.history = history
        self.diagnostic = diagnostic
        self.windowSize = windowSize
        self.now = now
        self.makeRequestID = makeRequestID
        self.makeExchangeID = makeExchangeID
        self.makeMessageID = makeMessageID
    }

    // MARK: Room CRUD (forwarded — rooms are derived, not owned)

    /// Forwards to the managing seam; returns the new room's stable id.
    @discardableResult
    public func createRoom(name: String) async -> ChatRoomID { await roomsManaging.createRoom(name: name) }
    /// Forwards a rename.
    public func renameRoom(_ id: ChatRoomID, to name: String) async { await roomsManaging.renameRoom(id, to: name) }
    /// Forwards the close-room flow (keep-≥1 enforced by the app seam).
    public func closeRoom(_ id: ChatRoomID) async { _ = await roomsManaging.requestCloseRoom(id) }
    /// Forwards an agent move; in-flight turns stay bound to their originating room.
    public func move(_ agent: AgentID, to room: ChatRoomID) async { await roomsManaging.setRoom(of: agent, to: room) }
    /// The active room derived from selection.
    public func activeRoomID() async -> ChatRoomID? { await roomsReading.activeRoomID() }
    /// All rooms, derived from the live `.chatRoom` workspaces.
    public func rooms() async -> [ChatRoom] { await roomsReading.rooms() }
    /// The mentionable agents in a room (for `@`-autocomplete).
    public func roster(inRoom room: ChatRoomID) async -> [AgentIdentitySnapshot] {
        await roster.current(inRoom: room)
    }

    /// Live lifecycle of every known agent — read fresh from the seam (no cache). The channel view
    /// uses this for in-flight running / needs-input visibility, re-fetching on ``lifecycleVersion``.
    public func lifecycleSnapshot() async -> [AgentID: AgentLifecycle] { await lifecycle.current() }

    // MARK: Sending

    /// Sends `body` to `mentions` (resolved against `room`'s agents only) as one exchange.
    public func send(in room: ChatRoomID, _ body: String,
                     to mentions: [AgentMention], origin: PromptOrigin) async {
        let roomAgents = await roster.current(inRoom: room)
        let byID = Dictionary(roomAgents.map { ($0.agentID, $0) }, uniquingKeysWith: { a, _ in a })
        let targets = mentions.compactMap { byID[$0.agentID] }
        diag("send room=\(room.raw.uuidString.prefix(8)) mentions=\(mentions.count) resolvedTargets=\(targets.count)")
        guard !targets.isEmpty else {
            diag("send room=\(room.raw.uuidString.prefix(8)) ABORT: no targets resolved (roomAgents=\(roomAgents.count))")
            return
        }

        let exchangeID = makeExchangeID()
        let prompt = OutgoingPrompt(exchangeID: exchangeID, roomID: room, origin: origin,
                                    bodyText: body, targets: targets, sentAt: now())
        var outcomes: [AgentID: ReplyOutcome] = [:]
        for t in targets { outcomes[t.agentID] = .pending }
        let exchange = Exchange(prompt: prompt, outcomes: outcomes)

        await history.append(exchange, in: room)
        appendToWindow(exchange, in: room)

        for t in targets {
            let state = await lifecycle.state(of: t.agentID)
            if state == .needsInput {
                heldForNeedsInput[t.agentID, default: []].append(
                    HeldPrompt(exchangeID: exchangeID, roomID: room, agent: t.agentID, body: body))
                diag("hold agent=\(t.agentID.raw.uuidString.prefix(8)) exchange=\(exchangeID.raw.uuidString.prefix(8)) (needsInput)")
            } else {
                await injectAndBind(body, exchange: exchangeID, room: room, agent: t.agentID)
            }
        }
    }

    /// Injects `body` (no marker) into `agent` and, on success, binds a ``ChatTurn`` to the agent's
    /// FIFO so its next completion routes to `exchange`. On failure marks `.failedToDispatch`.
    private func injectAndBind(_ body: String, exchange: ExchangeID, room: ChatRoomID, agent: AgentID) async {
        let ok = await injector.inject(body, into: agent)
        if ok {
            turnQueueByAgent[agent, default: []].append(
                ChatTurn(exchangeID: exchange, roomID: room, agent: agent))
            diag("inject agent=\(agent.raw.uuidString.prefix(8)) exchange=\(exchange.raw.uuidString.prefix(8)) ok=true queueDepth=\(turnQueueByAgent[agent]?.count ?? 0)")
        } else {
            diag("inject agent=\(agent.raw.uuidString.prefix(8)) exchange=\(exchange.raw.uuidString.prefix(8)) ok=false -> failedToDispatch")
            setOutcome(.failedToDispatch, agent: agent, exchange: exchange, room: room)
        }
    }

    /// Forwards an earlier reply (quoted + note) to new targets as a fresh exchange.
    public func forward(_ source: MessageID, quoted: String, note: String,
                        to mentions: [AgentMention], in room: ChatRoomID) async {
        let body = "\"\(quoted)\"\n\(note)"
        await send(in: room, body, to: mentions, origin: .forward(sourceMessageID: source))
    }

    // MARK: Turn events

    /// Consumes a normalized turn event from the app bridge.
    public func handle(_ event: AgentTurnEvent) {
        switch event {
        case let .promptSubmitted(agent):
            // Diagnostic only — binding happens at inject time, not here.
            diag("promptSubmit agent=\(agent.raw.uuidString.prefix(8)) queueDepth=\(turnQueueByAgent[agent]?.count ?? 0)")
        case let .turnCompleted(agent, finalMessage):
            guard var queue = turnQueueByAgent[agent], !queue.isEmpty else {
                diag("turnCompleted agent=\(agent.raw.uuidString.prefix(8)) UNMATCHED: no queued chat turn — reply dropped (chars=\(finalMessage.count))")
                return
            }
            let turn = queue.removeFirst()
            turnQueueByAgent[agent] = queue
            diag("turnCompleted agent=\(agent.raw.uuidString.prefix(8)) -> attach exchange=\(turn.exchangeID.raw.uuidString.prefix(8)) chars=\(finalMessage.count)")
            attachReply(finalMessage, agent: agent, exchange: turn.exchangeID, room: turn.roomID)
        case let .agentSessionStarted(agent):
            // Diagnostic only. `sessionStart` cannot reliably distinguish a prompt lost in a pre-agent
            // shell from one typed-ahead into a *starting* agent that does receive it — both are injected
            // before `sessionStart` fires (~2s later). Discarding here wrongly failed legitimate sends
            // (codex regression). The real fix for "sent to a not-yet-running agent" is hold-until-live.
            diag("sessionStart agent=\(agent.raw.uuidString.prefix(8)) (no-op for correlation)")
        }
    }

    /// Flushes held prompts when an agent leaves `needsInput`. Always bumps ``lifecycleVersion`` so the
    /// channel view re-reads live status (including transitions *into* `needsInput`).
    public func onLifecycleChange(_ change: AgentLifecycleChange) async {
        lifecycleVersion &+= 1
        guard change.state == .running || change.state == .idle else { return }
        guard let held = heldForNeedsInput.removeValue(forKey: change.agent), !held.isEmpty else { return }
        for h in held {
            await injectAndBind(h.body, exchange: h.exchangeID, room: h.roomID, agent: h.agent)
        }
    }

    /// Marks an agent's in-flight chat work `.tabClosed` and clears its queue/holds.
    public func onAgentClosed(_ agent: AgentID) {
        if let queued = turnQueueByAgent.removeValue(forKey: agent) {
            for turn in queued { setOutcome(.tabClosed, agent: agent, exchange: turn.exchangeID, room: turn.roomID) }
        }
        if let held = heldForNeedsInput.removeValue(forKey: agent) {
            for h in held { setOutcome(.tabClosed, agent: agent, exchange: h.exchangeID, room: h.roomID) }
        }
    }

    // MARK: Paging

    /// Pages older exchanges for `room` from the store into the window.
    public func loadEarlier(in room: ChatRoomID) async {
        guard var ch = window[room], let oldest = ch.exchanges.first else {
            let recent = await history.recent(in: room, limit: windowSize)
            window[room] = RoomChannel(roomID: room, exchanges: recent, reachedStart: recent.count < windowSize)
            channels[room] = recent
            return
        }
        let older = await history.page(in: room, before: oldest.id, limit: windowSize)
        ch.exchanges = older + ch.exchanges
        ch.reachedStart = older.count < windowSize
        window[room] = ch
        channels[room] = ch.exchanges
    }

    // MARK: Private helpers

    /// Emits a diagnostic line when a sink is wired; a no-op (and zero string-building cost) otherwise.
    private func diag(_ message: @autoclosure () -> String) {
        guard let diagnostic else { return }
        diagnostic(message())
    }

    private func appendToWindow(_ exchange: Exchange, in room: ChatRoomID) {
        var ch = window[room] ?? RoomChannel(roomID: room, exchanges: [], reachedStart: false)
        ch.exchanges.append(exchange)
        if ch.exchanges.count > windowSize { ch.exchanges.removeFirst(ch.exchanges.count - windowSize) }
        window[room] = ch
        channels[room] = ch.exchanges
    }

    private func setOutcome(_ outcome: ReplyOutcome, agent: AgentID, exchange: ExchangeID, room: ChatRoomID) {
        guard var ch = window[room], let i = ch.exchanges.firstIndex(where: { $0.id == exchange }) else { return }
        ch.exchanges[i].outcomes[agent] = outcome
        window[room] = ch
        channels[room] = ch.exchanges
        let updated = ch.exchanges[i]
        Task { await history.update(updated, in: room) }
    }

    private func attachReply(_ finalMessage: String, agent: AgentID, exchange: ExchangeID, room: ChatRoomID) {
        guard var ch = window[room], let i = ch.exchanges.firstIndex(where: { $0.id == exchange }) else { return }
        let from = ch.exchanges[i].prompt.targets.first { $0.agentID == agent }
            ?? AgentIdentitySnapshot(agentID: agent, title: "", kind: .claudeCode, cwdDisplay: "", branch: nil)
        let reply = Reply(id: makeMessageID(), exchangeID: exchange, from: from,
                          markdownBody: finalMessage, receivedAt: now())
        ch.exchanges[i].outcomes[agent] = .replied(reply)
        window[room] = ch
        channels[room] = ch.exchanges
        let updated = ch.exchanges[i]
        Task { await history.update(updated, in: room) }
        Task { [notifier, roomsReading] in
            if await roomsReading.activeRoomID() != room { await notifier.notifyRoomCompletion(room) }
        }
    }
}
