import AppKit
import Foundation
import CmuxChatRoomCore

/// Maps `~` over the user's home directory for display.
@MainActor
private func abbreviateHome(_ path: String) -> String {
    let home = NSHomeDirectory()
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
}

// MARK: Rooms (read + manage)

/// ``RoomWorkspaceReading`` + ``RoomWorkspaceManaging`` over `TabManager`. Rooms are derived from
/// live `.chatRoom` workspaces; mutations call the `TabManager+ChatRoom` operations.
@MainActor
final class AppRoomWorkspaceSeam: RoomWorkspaceReading, RoomWorkspaceManaging {
    private weak var tabManager: TabManager?
    nonisolated let changes: AsyncStream<Void>
    init(tabManager: TabManager) {
        self.tabManager = tabManager
        self.changes = AsyncStream { _ in }
    }

    func rooms() async -> [ChatRoom] {
        (tabManager?.chatRoomWorkspaces ?? []).compactMap { ws in
            guard let rid = ws.chatRoomID else { return nil }
            return ChatRoom(id: ChatRoomID(raw: rid), name: ws.roomName ?? ws.title)
        }
    }

    func activeRoomID() async -> ChatRoomID? {
        tabManager?.activeChatRoomID.map { ChatRoomID(raw: $0) }
    }

    func createRoom(name: String) async -> ChatRoomID {
        ChatRoomID(raw: tabManager?.createRoomWorkspace(name: name) ?? UUID())
    }

    func renameRoom(_ id: ChatRoomID, to name: String) async {
        tabManager?.renameRoom(chatRoomID: id.raw, to: name)
    }

    func requestCloseRoom(_ id: ChatRoomID) async -> Bool {
        tabManager?.closeRoom(chatRoomID: id.raw) ?? false
    }

    func setRoom(of agent: AgentID, to room: ChatRoomID) async {
        tabManager?.setRoom(ofAgent: agent.raw, toRoom: room.raw)
    }
}

// MARK: Roster

/// ``AgentRosterProviding`` over `TabManager`. A room's mentionable set = `.agent` workspaces with
/// `roomID == room` and a supported `AgentKind` (chat-supported); legacy/unknown agents are excluded.
@MainActor
final class AppRosterSeam: AgentRosterProviding {
    private weak var tabManager: TabManager?
    nonisolated let changes: AsyncStream<Void>
    init(tabManager: TabManager) {
        self.tabManager = tabManager
        self.changes = AsyncStream { _ in }
    }

    func current(inRoom room: ChatRoomID) async -> [AgentIdentitySnapshot] {
        (tabManager?.agentWorkspaces(inRoom: room.raw) ?? []).compactMap { ws in
            guard let raw = ws.agentKindRaw, let kind = AgentKind(rawValue: raw) else { return nil }
            return AgentIdentitySnapshot(
                agentID: AgentID(raw: ws.id),
                title: ws.customTitle ?? ws.title,
                kind: kind,
                cwdDisplay: abbreviateHome(ws.currentDirectory),
                branch: ws.gitBranch?.branch
            )
        }
    }
}

// MARK: Lifecycle

/// ``AgentLifecycleReading`` over the existing `Workspace.agentLifecycleStatesByPanelId`.
@MainActor
final class AppLifecycleSeam: AgentLifecycleReading {
    private weak var tabManager: TabManager?
    nonisolated let changes: AsyncStream<AgentLifecycleChange>
    init(tabManager: TabManager) {
        self.tabManager = tabManager
        self.changes = AsyncStream { _ in }
    }

    func current() async -> [AgentID: AgentLifecycle] {
        var out: [AgentID: AgentLifecycle] = [:]
        for ws in tabManager?.agentWorkspaces ?? [] {
            out[AgentID(raw: ws.id)] = Self.aggregateLifecycle(for: ws)
        }
        return out
    }

    func state(of agent: AgentID) async -> AgentLifecycle {
        guard let ws = tabManager?.agentWorkspace(id: agent.raw) else { return .unknown }
        return Self.aggregateLifecycle(for: ws)
    }

    /// Aggregates a workspace's per-panel agent states: needsInput wins, then running, then idle.
    static func aggregateLifecycle(for ws: Workspace) -> AgentLifecycle {
        var sawRunning = false
        var sawIdle = false
        for byName in ws.agentLifecycleStatesByPanelId.values {
            for state in byName.values {
                switch state {
                case .needsInput: return .needsInput
                case .running: sawRunning = true
                case .idle: sawIdle = true
                case .unknown: break
                }
            }
        }
        if sawRunning { return .running }
        if sawIdle { return .idle }
        return .unknown
    }
}

// MARK: Injection

/// ``PromptInjecting`` over terminal surfaces — non-focus-stealing `sendInputResult` + submit.
@MainActor
final class AppInjector: PromptInjecting {
    private weak var tabManager: TabManager?
    init(tabManager: TabManager) { self.tabManager = tabManager }

    func inject(_ text: String, into agent: AgentID) async -> Bool {
        guard let ws = tabManager?.agentWorkspace(id: agent.raw),
              let panelId = ws.focusedPanelId,
              let panel = ws.terminalPanel(for: panelId)
        else {
#if DEBUG
            cmuxDebugLog("chatroom.inject agent=\(agent.raw.uuidString.prefix(8)) FAIL: no agent workspace / focused terminal panel")
#endif
            return false
        }
        // Insert the body (including the trailing correlation marker) through the paste path so
        // bracketed paste mode lands the multi-line text atomically — no embedded newline submits
        // early. Then deliver a single discrete Return so the TUI submits the whole prompt as one
        // turn. `sendInputResult` cannot be used here: it expands every "\n"/"\r" into a burst of
        // Return key events, which agent TUIs (Claude/Codex) coalesce as a paste and never submit.
        guard panel.sendText(text) else {
#if DEBUG
            cmuxDebugLog("chatroom.inject agent=\(agent.raw.uuidString.prefix(8)) FAIL: sendText (paste) rejected")
#endif
            return false
        }
        let submitted = panel.sendNamedKey("enter")
#if DEBUG
        cmuxDebugLog("chatroom.inject agent=\(agent.raw.uuidString.prefix(8)) panel=\(panelId.uuidString.prefix(8)) chars=\(text.count) paste=ok submit(enter)=\(submitted)")
#endif
        return submitted
    }
}

// MARK: Notify

/// ``ChatNotifying`` — forwards completion badges to the controller (which republishes for the UI).
@MainActor
final class AppNotifier: ChatNotifying {
    var onBadge: ((ChatRoomID) -> Void)?
    func notifyRoomCompletion(_ room: ChatRoomID) async { onBadge?(room) }
}
