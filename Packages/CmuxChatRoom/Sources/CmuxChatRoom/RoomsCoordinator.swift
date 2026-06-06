public import Foundation
public import CmuxChatRoomCore

/// `@MainActor @Observable` orchestrator for the chat room. Owns channel/correlation/history state
/// only; rooms, roster, and lifecycle are **derived** through read seams.
///
/// Correlation is marker-based and room-scoped: a reply routes back to a channel **only** if its
/// prompt carried a ``ChatPromptMarker`` minted by ``send(in:_:to:origin:)``. Direct (user-typed)
/// turns carry no marker and are dropped.
@MainActor @Observable
public final class RoomsCoordinator {
    /// Per-room windowed channel state (UI reads this).
    public private(set) var channels: [ChatRoomID: [Exchange]] = [:]

    private var window: [ChatRoomID: RoomChannel] = [:]
    private var turnQueueBySurface: [SurfaceID: [TurnBinding]] = [:]
    private var pendingByRequest: [ChatRequestID: PendingInjection] = [:]
    private var heldForNeedsInput: [AgentID: [HeldPrompt]] = [:]

    private let roomsReading: any RoomWorkspaceReading
    private let roomsManaging: any RoomWorkspaceManaging
    private let roster: any AgentRosterProviding
    private let lifecycle: any AgentLifecycleReading
    private let injector: any PromptInjecting
    private let notifier: any ChatNotifying
    private let history: any ChatHistoryStore
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

    // MARK: Sending

    /// Sends `body` to `mentions` (resolved against `room`'s agents only) as one exchange.
    public func send(in room: ChatRoomID, _ body: String,
                     to mentions: [AgentMention], origin: PromptOrigin) async {
        let roomAgents = await roster.current(inRoom: room)
        let byID = Dictionary(roomAgents.map { ($0.agentID, $0) }, uniquingKeysWith: { a, _ in a })
        let targets = mentions.compactMap { byID[$0.agentID] }
        guard !targets.isEmpty else { return }

        let exchangeID = makeExchangeID()
        let prompt = OutgoingPrompt(exchangeID: exchangeID, roomID: room, origin: origin,
                                    bodyText: body, targets: targets, sentAt: now())
        var outcomes: [AgentID: ReplyOutcome] = [:]
        for t in targets { outcomes[t.agentID] = .pending }
        let exchange = Exchange(prompt: prompt, outcomes: outcomes)

        await history.append(exchange, in: room)
        appendToWindow(exchange, in: room)

        for t in targets {
            let requestID = makeRequestID()
            let bodyWithMarker = ChatPromptMarker.inject(requestID, into: body)
            let state = await lifecycle.state(of: t.agentID)
            if state == .needsInput {
                heldForNeedsInput[t.agentID, default: []].append(
                    HeldPrompt(requestID: requestID, exchangeID: exchangeID, roomID: room,
                               agent: t.agentID, bodyWithMarker: bodyWithMarker))
            } else {
                pendingByRequest[requestID] = PendingInjection(
                    requestID: requestID, exchangeID: exchangeID, roomID: room, agent: t.agentID)
                let ok = await injector.inject(bodyWithMarker, into: t.agentID)
                if !ok {
                    pendingByRequest[requestID] = nil
                    setOutcome(.failedToDispatch, agent: t.agentID, exchange: exchangeID, room: room)
                }
            }
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
        case let .promptSubmitted(surface, rawPromptText):
            let (id, _) = ChatPromptMarker.extract(from: rawPromptText)
            if let id, let pending = pendingByRequest.removeValue(forKey: id) {
                turnQueueBySurface[surface, default: []].append(
                    .chatOrigin(request: id, exchange: pending.exchangeID,
                                room: pending.roomID, agent: pending.agent))
            } else {
                turnQueueBySurface[surface, default: []].append(.direct)
            }
        case let .turnCompleted(surface, finalMessage):
            guard var queue = turnQueueBySurface[surface], !queue.isEmpty else { return }
            let binding = queue.removeFirst()
            turnQueueBySurface[surface] = queue
            guard case let .chatOrigin(_, exchangeID, room, agent) = binding else { return }
            attachReply(finalMessage, agent: agent, exchange: exchangeID, room: room)
        }
    }

    /// Flushes held prompts when an agent leaves `needsInput`.
    public func onLifecycleChange(_ change: AgentLifecycleChange) async {
        guard change.state == .running || change.state == .idle else { return }
        guard let held = heldForNeedsInput.removeValue(forKey: change.agent), !held.isEmpty else { return }
        for h in held {
            pendingByRequest[h.requestID] = PendingInjection(
                requestID: h.requestID, exchangeID: h.exchangeID, roomID: h.roomID, agent: h.agent)
            let ok = await injector.inject(h.bodyWithMarker, into: h.agent)
            if !ok {
                pendingByRequest[h.requestID] = nil
                setOutcome(.failedToDispatch, agent: h.agent, exchange: h.exchangeID, room: h.roomID)
            }
        }
    }

    /// Marks an agent's in-flight chat work `.tabClosed` and clears its queues/holds.
    public func onAgentClosed(_ agent: AgentID) {
        for (req, p) in pendingByRequest where p.agent == agent {
            pendingByRequest[req] = nil
            setOutcome(.tabClosed, agent: agent, exchange: p.exchangeID, room: p.roomID)
        }
        if let held = heldForNeedsInput.removeValue(forKey: agent) {
            for h in held { setOutcome(.tabClosed, agent: agent, exchange: h.exchangeID, room: h.roomID) }
        }
        for (surface, queue) in turnQueueBySurface {
            turnQueueBySurface[surface] = queue.filter { binding in
                if case let .chatOrigin(_, _, _, a) = binding { return a != agent }
                return true
            }
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
