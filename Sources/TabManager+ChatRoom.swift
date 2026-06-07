import Foundation
import CmuxChatRoomCore

/// Chat-room creation, membership, and close operations on `TabManager`.
///
/// Rooms and agents are both workspaces (`WorkspaceRole`); membership is the agent's `roomID`
/// referencing a room's stable `chatRoomID`. See the design spec §4.8–§4.11.
@MainActor
extension TabManager {
    // MARK: Lookups

    /// All chat-room workspaces (top sidebar section), in tab order.
    var chatRoomWorkspaces: [Workspace] {
        tabs.filter { $0.workspaceRole == .chatRoom }
    }

    /// All agent workspaces (bottom sidebar section), in tab order.
    var agentWorkspaces: [Workspace] {
        tabs.filter { $0.workspaceRole == .agent }
    }

    /// The room workspace backing `chatRoomID`, if present.
    func roomWorkspace(forChatRoomID chatRoomID: UUID) -> Workspace? {
        tabs.first { $0.workspaceRole == .chatRoom && $0.chatRoomID == chatRoomID }
    }

    /// The agent workspace with `id`, if it is an agent.
    func agentWorkspace(id: UUID) -> Workspace? {
        tabs.first { $0.workspaceRole == .agent && $0.id == id }
    }

    /// Agents belonging to a room (membership by `roomID`).
    func agentWorkspaces(inRoom chatRoomID: UUID) -> [Workspace] {
        tabs.filter { $0.workspaceRole == .agent && $0.roomID == chatRoomID }
    }

    /// The active room id derived from selection: selected room → its `chatRoomID`; selected agent →
    /// its `roomID`; otherwise the first room (fail-safe so room-scoped actions always resolve).
    var activeChatRoomID: UUID? {
        if let selected = selectedWorkspace {
            if selected.workspaceRole == .chatRoom { return selected.chatRoomID }
            if selected.workspaceRole == .agent, let rid = selected.roomID { return rid }
        }
        return chatRoomWorkspaces.first?.chatRoomID
    }

    // MARK: Migration / bootstrap

    /// Guarantees at least one chat room exists, and that every agent has a `roomID`.
    ///
    /// Migrates a pre-rooms session: legacy terminal tabs are already `.agent` (the field default);
    /// here we synthesize a default room if none exists and stamp any room-less agent into it.
    @discardableResult
    func ensureDefaultRoomExists() -> UUID {
        let existing = chatRoomWorkspaces.compactMap(\.chatRoomID)
        let roomID: UUID
        if let first = existing.first {
            roomID = first
        } else {
            roomID = createRoomWorkspace(
                name: String(localized: "chatroom.defaultRoomName", defaultValue: "general"),
                select: false
            )
        }
        for agent in agentWorkspaces where agent.roomID == nil {
            agent.roomID = roomID
        }
        return roomID
    }

    // MARK: Room CRUD

    /// Creates a `.chatRoom` workspace with a fresh stable `chatRoomID`. Returns that id.
    @discardableResult
    func createRoomWorkspace(name: String, select: Bool = true) -> UUID {
        let ws = addWorkspace(
            title: name,
            select: select,
            eagerLoadTerminal: false,
            autoWelcomeIfNeeded: false
        )
        let chatRoomID = UUID()
        ws.workspaceRole = .chatRoom
        ws.chatRoomID = chatRoomID
        ws.roomName = name
        ws.roomID = nil
        ws.agentKindRaw = nil
        ws.setCustomTitle(name)
        // Give each room a distinct color so the top sidebar section reads like Slack channels.
        let palette = ["#7B5CFF", "#43B0C9", "#C98F43", "#5EC27B", "#C0392B", "#9B59B6", "#2E86DE"]
        let existingRoomCount = chatRoomWorkspaces.filter { $0.id != ws.id }.count
        ws.setCustomColor(palette[existingRoomCount % palette.count])
        return chatRoomID
    }

    /// Renames the room backing `chatRoomID`.
    func renameRoom(chatRoomID: UUID, to name: String) {
        guard let ws = roomWorkspace(forChatRoomID: chatRoomID) else { return }
        ws.roomName = name
        ws.setCustomTitle(name)
    }

    /// Moves an agent into another room (rewrites `roomID`). In-flight chat turns stay bound to the
    /// originating room by the coordinator.
    func setRoom(ofAgent agentID: UUID, toRoom chatRoomID: UUID) {
        agentWorkspace(id: agentID)?.roomID = chatRoomID
    }

    // MARK: Agent creation (directory + model; no worktree management)

    /// Creates an agent workspace in `directory`, stamped with `kind` and `roomID`, and starts the
    /// agent CLI. Returns the new workspace.
    @discardableResult
    func addAgentWorkspace(kind: AgentKind, directory: String, roomID: UUID, select: Bool = true) -> Workspace {
        let ws = addWorkspace(
            title: defaultAgentTitle(kind: kind, roomID: roomID),
            workingDirectory: directory,
            inheritWorkingDirectory: false,
            select: select,
            eagerLoadTerminal: true,
            autoWelcomeIfNeeded: false
        )
        ws.workspaceRole = .agent
        ws.roomID = roomID
        ws.agentKindRaw = kind.rawValue
        ws.chatRoomID = nil
        ws.roomName = nil
        ws.setCustomTitle(ws.title)
        // Launch the agent CLI in the new surface. cmux's existing hook infrastructure installs the
        // prompt-submit/stop hooks for the agent process; the chat bridge taps those events.
        if let panelId = ws.focusedPanelId {
            let command = Self.launchCommand(for: kind)
            _ = ws.terminalPanel(for: panelId)?.sendInputResult(command + "\r")
        }
        return ws
    }

    /// Auto-name like "claude code 1" within the agent's room.
    private func defaultAgentTitle(kind: AgentKind, roomID: UUID) -> String {
        let base = Self.displayName(for: kind)
        let count = agentWorkspaces(inRoom: roomID).filter { $0.agentKindRaw == kind.rawValue }.count
        return "\(base) \(count + 1)"
    }

    /// Display base name for an agent kind.
    static func displayName(for kind: AgentKind) -> String {
        switch kind {
        case .claudeCode: return "claude code"
        case .codex: return "codex"
        case .cursor: return "cursor"
        }
    }

    /// The shell command that starts each agent CLI so its hooks fire back into cmux.
    ///
    /// **Claude:** must launch the **bundled `claude` wrapper** (sibling of the bundled cmux CLI), which
    /// injects `--session-id`/`--settings` so Claude Code hooks reach this app. Bare `claude` resolves
    /// to the real binary with no hooks — the shell-integration `claude` function is not reliably in
    /// effect for this auto-injected launch line, so we invoke the wrapper by absolute path (falling
    /// back to PATH `claude` only if the bundled wrapper is unavailable).
    ///
    /// **Codex / Cursor:** do not auto-inject — their hooks must be installed into their config
    /// (`~/.codex/hooks.json`, …) first, else they never call `cmux hooks …` and turns never reach the
    /// channel. `--yes` is REQUIRED: without it the installer prints a diff and waits for confirmation
    /// on stdin; with output redirected to `/dev/null` that prompt is invisible and never answered, so
    /// the hooks file is never written. `${CMUX_BUNDLED_CLI_PATH:-cmux}` prefers the bundled CLI.
    static func launchCommand(for kind: AgentKind) -> String {
        let cli = "${CMUX_BUNDLED_CLI_PATH:-cmux}"
        switch kind {
        case .claudeCode:
            // Resolve the bundled `claude` wrapper from `Bundle.main` (deterministic — `CMUX_BUNDLED_CLI_PATH`
            // can point at a standalone build-products `cmux`, whose sibling has no `claude`). The wrapper
            // injects `--session-id`/`--settings` so Claude Code hooks reach this app; bare `claude` is the
            // real binary with no hooks. Single-quote the path for the shell (paths contain spaces).
            if let wrapper = Bundle.main.resourceURL?.appendingPathComponent("bin/claude").path,
               FileManager.default.isExecutableFile(atPath: wrapper) {
                return "'\(wrapper)'"
            }
            return "claude"
        case .codex: return "\(cli) hooks codex install --yes >/dev/null 2>&1; codex"
        case .cursor: return "\(cli) hooks cursor install --yes >/dev/null 2>&1; cursor-agent"
        }
    }

    // MARK: Close

    /// Closes a room: terminates its member agents, then the room workspace. Refuses if it would
    /// leave zero rooms (keep ≥1). No filesystem side effects (cmux manages no worktrees). Returns
    /// `true` if closed. The room-workspace close sets ``chatRoomCloseBypass`` so the `closeWorkspace`
    /// gate (§4.10) doesn't recurse back here; member agents close *through* the gate, which reconciles
    /// the coordinator via `onAgentClosed`.
    @discardableResult
    func closeRoom(chatRoomID: UUID) -> Bool {
        guard chatRoomWorkspaces.count > 1 else { return false }   // keep ≥1 room
        guard let room = roomWorkspace(forChatRoomID: chatRoomID) else { return false }
        for member in agentWorkspaces(inRoom: chatRoomID) {
            closeWorkspace(member)   // gate path → onAgentClosed + teardown
        }
        chatRoomCloseBypass = true
        defer { chatRoomCloseBypass = false }
        closeWorkspace(room)
        return true
    }
}
