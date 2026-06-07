import AppKit
import Foundation
import CMUXWorkstream
import CmuxChatRoomCore
import CmuxChatRoom

/// App-side composition root for the chat room: owns the ``RoomsCoordinator``, the seam
/// implementations over `TabManager`/terminal surfaces, and the bridge from the hook pipeline
/// (`prompt-submit`/`stop`) into ``AgentTurnEvent``s.
///
/// One instance is configured at startup against the primary `TabManager`. Cross-window chat rooms
/// are out of scope for v1.
@MainActor
final class ChatRoomController: ObservableObject {
    static var shared: ChatRoomController?

    let coordinator: RoomsCoordinator
    private weak var tabManager: TabManager?
    private var observers: [NSObjectProtocol] = []
    /// Rooms with an unread completion while not active (drives the sidebar dot).
    @Published private(set) var badgedRoomIDs: Set<UUID> = []

    /// Posted by `TerminalController.v2FeedPush` with the raw `WorkstreamEvent` in `userInfo["event"]`.
    static let rawFeedEventNotification = Notification.Name("cmux.chatRoom.rawFeedEvent")
    /// Posted by `Workspace.setAgentLifecycle`; `userInfo["workspaceId"]` is the agent's `UUID`.
    static let lifecycleChangedNotification = Notification.Name("cmux.chatRoom.lifecycleChanged")

    /// Builds the controller and starts observing the hook + lifecycle notifications.
    init(tabManager: TabManager) {
        self.tabManager = tabManager
        let historyDir = Self.historyDirectory()
        let history = JSONChatHistoryStore(directory: historyDir)
        let roomSeam = AppRoomWorkspaceSeam(tabManager: tabManager)
        let rosterSeam = AppRosterSeam(tabManager: tabManager)
        let lifecycleSeam = AppLifecycleSeam(tabManager: tabManager)
        let injector = AppInjector(tabManager: tabManager)
        let notifier = AppNotifier()
        coordinator = RoomsCoordinator(
            roomsReading: roomSeam, roomsManaging: roomSeam, roster: rosterSeam,
            lifecycle: lifecycleSeam, injector: injector, notifier: notifier, history: history,
            diagnostic: Self.makeDiagnosticSink()
        )
        notifier.onBadge = { [weak self] roomID in self?.badge(roomID) }
        observeNotifications()
    }

    /// Binds the singleton to the **visible window's** `TabManager` (cmux is multi-window; the
    /// App-level `@StateObject` is not the instance the sidebar renders). Call from the window
    /// registration path. Idempotent — binds once and ensures a default room exists.
    static func configure(tabManager: TabManager) {
        guard shared == nil else { return }
        let controller = ChatRoomController(tabManager: tabManager)
        shared = controller
        controller.bootstrapDefaultRoom()
#if DEBUG
        cmuxDebugLog("chatroom.configure bound tm=\(ObjectIdentifier(tabManager)) rooms=\(tabManager.chatRoomWorkspaces.count) agents=\(tabManager.agentWorkspaces.count)")
#endif
    }

    /// Ensures at least one chat room exists (idempotent).
    func bootstrapDefaultRoom() {
        // Intentionally does NOT auto-create a room. The app starts with **no chat rooms**; the user
        // creates the first one via the "CHAT ROOMS" `+`. (We still migrate any room-less agents from
        // a legacy session into a room so they aren't orphaned, but we never synthesize an empty
        // "general" room on a fresh start.)
        guard !(tabManager?.agentWorkspaces.contains(where: { $0.roomID == nil }) ?? false) else {
            tabManager?.ensureDefaultRoomExists()
            return
        }
    }

    /// Clears a room's unread badge (call when it becomes active).
    func clearBadge(_ roomID: UUID) {
        if badgedRoomIDs.contains(roomID) { badgedRoomIDs.remove(roomID) }
    }

    // MARK: Creation flows (AppKit prompts — no SwiftUI sheet state needed)

    /// Prompts for a room name and creates + selects a new chat room.
    func promptNewRoom() {
        guard let tabManager else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "chatroom.new.roomTitle", defaultValue: "New chat room")
        alert.addButton(withTitle: String(localized: "chatroom.create", defaultValue: "Create"))
        alert.addButton(withTitle: String(localized: "chatroom.cancel", defaultValue: "Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = String(localized: "chatroom.new.roomPlaceholder", defaultValue: "room name")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = name.isEmpty ? String(localized: "chatroom.defaultRoomName", defaultValue: "general") : name
        let rid = tabManager.createRoomWorkspace(name: final)
        if let ws = tabManager.roomWorkspace(forChatRoomID: rid) { tabManager.selectTab(ws) }
    }

    /// Prompts for a directory + agent model, then creates + selects a new agent in `roomID`.
    func promptNewAgent(roomID: UUID) {
        guard let tabManager else { return }
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = String(localized: "chatroom.new.chooseDir", defaultValue: "Choose directory")
        openPanel.message = String(localized: "chatroom.new.agentDirMessage", defaultValue: "Choose the working directory for the new agent")
        guard openPanel.runModal() == .OK, let dir = openPanel.url?.path else { return }

        let alert = NSAlert()
        alert.messageText = String(localized: "chatroom.new.agentModel", defaultValue: "Agent model")
        alert.addButton(withTitle: "Claude Code")
        alert.addButton(withTitle: "Codex")
        alert.addButton(withTitle: "Cursor")
        alert.addButton(withTitle: String(localized: "chatroom.cancel", defaultValue: "Cancel"))
        let kind: AgentKind
        switch alert.runModal() {
        case .alertFirstButtonReturn: kind = .claudeCode
        case .alertSecondButtonReturn: kind = .codex
        case .alertThirdButtonReturn: kind = .cursor
        default: return
        }
        let ws = tabManager.addAgentWorkspace(kind: kind, directory: dir, roomID: roomID)
        tabManager.selectTab(ws)
    }

    private func badge(_ roomID: ChatRoomID) {
        badgedRoomIDs.insert(roomID.raw)
    }

    private static func historyDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("cmux/ChatRoomHistory", isDirectory: true)
    }

    // MARK: Hook + lifecycle bridge

    private func observeNotifications() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: Self.rawFeedEventNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let event = note.userInfo?["event"] as? WorkstreamEvent else { return }
                self?.handleRawFeedEvent(event)
            }
        })
        observers.append(center.addObserver(forName: Self.lifecycleChangedNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let wsID = note.userInfo?["workspaceId"] as? UUID else { return }
                self?.handleLifecycleChange(workspaceID: wsID)
            }
        })
    }

    /// A diagnostic sink wired to the unified debug log in DEBUG builds, `nil` in release (so the
    /// coordinator skips building diagnostic strings entirely).
    private static func makeDiagnosticSink() -> ((String) -> Void)? {
#if DEBUG
        return { cmuxDebugLog("chatroom.coord \($0)") }
#else
        return nil
#endif
    }

    private func handleRawFeedEvent(_ event: WorkstreamEvent) {
#if DEBUG
        let wsShort = (event.workspaceId ?? "nil").prefix(8)
        cmuxDebugLog("chatroom.bridge rawFeedEvent hook=\(String(describing: event.hookEventName)) ws=\(wsShort)")
#endif
        guard let tabManager else {
#if DEBUG
            cmuxDebugLog("chatroom.bridge drop: no tabManager")
#endif
            return
        }
        guard let wsIDString = event.workspaceId, let wsID = UUID(uuidString: wsIDString) else {
#if DEBUG
            cmuxDebugLog("chatroom.bridge drop: missing/invalid workspaceId")
#endif
            return
        }
        guard let workspace = tabManager.tabs.first(where: { $0.id == wsID }) else {
#if DEBUG
            cmuxDebugLog("chatroom.bridge drop: workspace \(wsIDString.prefix(8)) not found")
#endif
            return
        }
        guard workspace.workspaceRole == .agent else {
#if DEBUG
            cmuxDebugLog("chatroom.bridge drop: ws \(wsIDString.prefix(8)) role=\(String(describing: workspace.workspaceRole)) not .agent")
#endif
            return
        }
        // Correlation is keyed by agent (one agent per tab in v1) — the agent IS the workspace, so no
        // surface/panel lookup is needed. Normalize the hook and let the unit-tested
        // `AgentTurnEvent.from(hook:)` make the routing decision so the app runs exactly the tested
        // logic (only top-level `stop` with a final message completes a turn; `subagentStop` does not).
        let agent = AgentID(raw: wsID)
        let kind: AgentHookKind
        switch event.hookEventName {
        case .userPromptSubmit: kind = .promptSubmit
        case .stop: kind = .stop
        case .subagentStop: kind = .subagentStop
        case .sessionStart: kind = .sessionStart
        default: kind = .other
        }
        let finalMessage = event.rawAssistantFinalMessage ?? event.assistantFinalMessage
        guard let turn = AgentTurnEvent.from(
            hook: AgentHookEvent(kind: kind, agent: agent, finalMessage: finalMessage)
        ) else {
#if DEBUG
            cmuxDebugLog("chatroom.bridge ignore hook=\(String(describing: event.hookEventName)) kind=\(kind.rawValue) hasFinal=\(finalMessage != nil)")
#endif
            return
        }
#if DEBUG
        cmuxDebugLog("chatroom.bridge -> handle agent=\(wsIDString.prefix(8)) kind=\(kind.rawValue) finalLen=\(finalMessage?.count ?? 0)")
#endif
        coordinator.handle(turn)
    }

    private func handleLifecycleChange(workspaceID: UUID) {
        guard let tabManager,
              let ws = tabManager.tabs.first(where: { $0.id == workspaceID }),
              ws.workspaceRole == .agent
        else { return }
        let state = AppLifecycleSeam.aggregateLifecycle(for: ws)
        Task { await coordinator.onLifecycleChange(AgentLifecycleChange(agent: AgentID(raw: workspaceID), state: state)) }
    }
}

/// Raw (non-whitespace-collapsed) accessors for the chat bridge. The struct retains the raw payload
/// even after the published event payload is redacted.
extension WorkstreamEvent {
    /// The submitted prompt text, raw if recoverable from `toolInputJSON`/`extraFieldsJSON`.
    var rawPromptText: String? {
        guard hookEventName == .userPromptSubmit else { return nil }
        return Self.rawString(fromJSON: toolInputJSON, keys: ["prompt", "text", "message", "body"])
            ?? Self.rawString(fromJSON: extraFieldsJSON, keys: ["prompt", "text", "message", "body"])
    }

    /// The agent's final message, verbatim (no whitespace collapse) — required for channel display.
    var rawAssistantFinalMessage: String? {
        guard hookEventName == .stop || hookEventName == .subagentStop else { return nil }
        return Self.rawString(fromJSON: extraFieldsJSON, keys: ["last_assistant_message", "lastAssistantMessage", "last_agent_message", "lastAgentMessage"])
            ?? Self.rawString(fromJSON: toolInputJSON, keys: ["last_assistant_message", "lastAssistantMessage"])
    }

    private static func rawString(fromJSON jsonString: String?, keys: [String]) -> String? {
        guard let jsonString,
              let data = jsonString.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        if let s = value as? String { return s.isEmpty ? nil : s }
        guard let dict = value as? [String: Any] else { return nil }
        for key in keys {
            if let s = dict[key] as? String, !s.isEmpty { return s }
        }
        for nestedKey in ["notification", "data"] {
            if let nested = dict[nestedKey] as? [String: Any] {
                for key in keys where (nested[key] as? String)?.isEmpty == false {
                    return nested[key] as? String
                }
            }
        }
        return nil
    }
}
