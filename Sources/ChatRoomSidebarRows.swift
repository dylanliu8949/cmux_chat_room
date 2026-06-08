import AppKit
import SwiftUI
import CmuxChatRoomCore

// MARK: Value snapshots (snapshot-boundary safe — rows never hold a store, see CLAUDE.md #2586)

/// Immutable snapshot of a chat-room row in the top sidebar section.
struct ChatRoomRowSnapshot: Equatable, Identifiable {
    let id: UUID                 // backing workspace id
    let chatRoomID: UUID
    let name: String
    let colorHex: String?
    let isSelected: Bool
    let hasUnread: Bool
    let isCollapsed: Bool        // true ⇒ this room's agent rows are hidden
}

/// Immutable snapshot of an agent row in the bottom sidebar section.
struct ChatAgentRowSnapshot: Equatable, Identifiable {
    let id: UUID                 // workspace id
    let title: String
    let cwdDisplay: String       // ~-abbreviated
    let branch: String?
    let lifecycle: AgentLifecycle
    let isSelected: Bool
    let isSupported: Bool        // false ⇒ unknown/unsupported AgentKind (not @-mentionable)
}

/// Sidebar text style honoring Settings → Sidebar (font size, path display, branch layout). Threaded
/// into chat rows so the existing sidebar-text settings keep working with the chat-room rows.
struct ChatSidebarRowStyle: Equatable {
    var fontScale: CGFloat = 1
    var lastSegmentPathOnly: Bool = false
    var branchOnOwnLine: Bool = true
}

/// Side-effect closures the sidebar provides to chat rows (kept as closures so rows stay value-fed).
@MainActor
struct ChatSidebarActions {
    var select: (UUID) -> Void
    var rename: (UUID, String) -> Void
    var closeWorkspace: (UUID) -> Void
    var newAgent: (UUID) -> Void          // arg: room's chatRoomID
    var moveAgent: (UUID, UUID) -> Void   // agentWorkspaceID, destination chatRoomID
    var toggleCollapse: (UUID) -> Void    // arg: room's chatRoomID
    var rooms: () -> [(chatRoomID: UUID, name: String)]
}

// MARK: Status badge

/// Lifecycle badge: rotating green spinner (running), dim dot (idle), pulsing amber + "!" (needs input).
/// Honors Reduce Motion (spinner → static ring; pulse → static) and carries an accessibility label.
struct AgentStatusBadge: View {
    let lifecycle: AgentLifecycle
    var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        let d = 9 * scale
        ZStack {
            switch lifecycle {
            case .running:
                Circle()
                    .trim(from: 0.1, to: 0.9)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: d, height: d)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
                    .onAppear { if !reduceMotion { spin = true } }
            case .needsInput:
                Circle()
                    .fill(Color.orange)
                    .frame(width: d, height: d)
                    .opacity(pulse ? 0.45 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                    .overlay(Text("!").font(.system(size: 7 * scale, weight: .bold)).foregroundStyle(.black))
                    .onAppear { if !reduceMotion { pulse = true } }
            case .idle, .unknown:
                Circle().fill(Color.secondary.opacity(0.5)).frame(width: 7 * scale, height: 7 * scale)
            }
        }
        .frame(width: 12 * scale, height: 12 * scale)
        .accessibilityLabel(Self.label(lifecycle))
    }

    static func label(_ l: AgentLifecycle) -> String {
        switch l {
        case .running: return String(localized: "chatroom.a11y.running", defaultValue: "running")
        case .idle: return String(localized: "chatroom.a11y.idle", defaultValue: "idle")
        case .needsInput: return String(localized: "chatroom.a11y.needsInput", defaultValue: "needs input")
        case .unknown: return String(localized: "chatroom.a11y.unknown", defaultValue: "unknown")
        }
    }
}

// MARK: Room row (top section)

/// A chat-room channel row that doubles as its agent group's header: colored `# name`, an unread dot,
/// and a `+` to add an agent into this room. Selecting shows its channel.
struct ChatRoomRowView: View {
    let snapshot: ChatRoomRowSnapshot
    let style: ChatSidebarRowStyle
    let actions: ChatSidebarActions
    @State private var editing = false
    @State private var draft = ""
    @State private var hovering = false

    private var color: Color {
        Color(nsColor: snapshot.colorHex.flatMap { NSColor(hex: $0) } ?? .systemPurple)
    }
    private var s: CGFloat { style.fontScale }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: snapshot.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9 * s, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16 * s, height: 18 * s, alignment: .center)
                // Collapse/expand is scoped to the chevron only — tapping the name (below)
                // selects the room without toggling its agent list.
                .contentShape(Rectangle())
                .onTapGesture { actions.toggleCollapse(snapshot.chatRoomID) }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(snapshot.isCollapsed
                    ? String(localized: "chatroom.a11y.expandRoom", defaultValue: "expand room")
                    : String(localized: "chatroom.a11y.collapseRoom", defaultValue: "collapse room"))
            Text("#").font(.system(size: 13 * s, weight: .bold)).foregroundStyle(color)
            if editing {
                TextField("", text: $draft, onCommit: commit)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13 * s, weight: .semibold))
                    .onExitCommand { editing = false }
            } else {
                Text(snapshot.name)
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundStyle(snapshot.isSelected ? color : .primary)
                    .lineLimit(1)
            }
            Spacer()
            if snapshot.hasUnread {
                Circle().fill(Color.red).frame(width: 7 * s, height: 7 * s)
            }
            Button { actions.newAgent(snapshot.chatRoomID) } label: {
                Image(systemName: "plus").font(.system(size: 11 * s, weight: .semibold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.55)
            .help(String(localized: "chatroom.action.addAgentToRoom", defaultValue: "Add agent to this room"))
        }
        .onHover { hovering = $0 }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(snapshot.isSelected ? color.opacity(0.18) : .clear)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(snapshot.isSelected ? color.opacity(0.6) : .clear, lineWidth: 1))
        )
        .contentShape(Rectangle())
        // Single tap on the row (name area) selects the room and shows its channel. Collapse is
        // handled by the chevron's own tap target above, so clicking the name never collapses.
        .onTapGesture { actions.select(snapshot.id) }
        .onTapGesture(count: 2) { beginEdit() }
        .contextMenu {
            Button(String(localized: "chatroom.action.rename", defaultValue: "Rename")) { beginEdit() }
            Button(String(localized: "chatroom.action.newAgent", defaultValue: "New agent")) { actions.newAgent(snapshot.chatRoomID) }
            Divider()
            Button(String(localized: "chatroom.action.closeRoom", defaultValue: "Close room"), role: .destructive) { actions.closeWorkspace(snapshot.id) }
        }
    }

    private func beginEdit() { draft = snapshot.name; editing = true }
    private func commit() {
        editing = false
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != snapshot.name { actions.rename(snapshot.id, trimmed) }
    }
}

// MARK: Room sub-header (bottom section group label)

/// Room label that groups its agents in the bottom section. The chevron toggles collapse; the `+`
/// adds an agent into this room (and its chat room). `onToggleCollapse`/`onAddAgent` are nil for the
/// non-room "unassigned" sentinel header.
struct ChatRoomSubHeaderView: View {
    let name: String
    var style: ChatSidebarRowStyle = .init()
    var isCollapsed: Bool = false
    var onToggleCollapse: (() -> Void)? = nil
    var onAddAgent: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button { onToggleCollapse?() } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8 * style.fontScale, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .disabled(onToggleCollapse == nil)

            Text(name).font(.system(size: 11 * style.fontScale, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if let onAddAgent {
                Button(action: onAddAgent) {
                    Image(systemName: "plus")
                        .font(.system(size: 10 * style.fontScale, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0.55)
                .help(String(localized: "chatroom.action.addAgentToRoom", defaultValue: "Add agent to this room"))
            }
        }
        .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Click anywhere on the header (besides the buttons) also toggles collapse.
        .onTapGesture { onToggleCollapse?() }
    }
}

// MARK: Agent row (bottom section — three lines + status badge)

/// Three-line agent tab: title · ~pwd · branch, with a live lifecycle badge (spec §3.2 / sidebar-v2.png).
/// Honors Settings → Sidebar font size, last-segment-path, and branch-on-own-line.
struct ChatAgentRowView: View {
    let snapshot: ChatAgentRowSnapshot
    let style: ChatSidebarRowStyle
    let actions: ChatSidebarActions
    @State private var editing = false
    @State private var draft = ""

    private var s: CGFloat { style.fontScale }

    private var pathText: String {
        guard style.lastSegmentPathOnly else { return snapshot.cwdDisplay }
        let last = (snapshot.cwdDisplay as NSString).lastPathComponent
        return last.isEmpty ? snapshot.cwdDisplay : last
    }

    private var rowBackground: Color {
        if snapshot.lifecycle == .needsInput { return Color.orange.opacity(snapshot.isSelected ? 0.18 : 0.10) }
        return snapshot.isSelected ? Color.primary.opacity(0.08) : .clear
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AgentStatusBadge(lifecycle: snapshot.lifecycle, scale: s).padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                if editing {
                    TextField("", text: $draft, onCommit: commit)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12 * s, weight: .semibold))
                        .onExitCommand { editing = false }
                } else {
                    Text(snapshot.title)
                        .font(.system(size: 12 * s, weight: .semibold))
                        .foregroundStyle(snapshot.isSupported ? .primary : .secondary)
                        .lineLimit(1)
                }
                Text(pathText)
                    .font(.system(size: 10 * s, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                if let branch = snapshot.branch {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 8 * s))
                        Text(branch).font(.system(size: 10 * s, design: .monospaced)).lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if snapshot.lifecycle == .needsInput {
                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 11 * s)).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(rowBackground))
        .contentShape(Rectangle())
        .onTapGesture { actions.select(snapshot.id) }
        .onTapGesture(count: 2) { beginEdit() }
        .contextMenu { menu }
    }

    @ViewBuilder private var menu: some View {
        Button(String(localized: "chatroom.action.rename", defaultValue: "Rename")) { beginEdit() }
        let rooms = actions.rooms()
        if rooms.count > 1 {
            Menu(String(localized: "chatroom.action.moveToRoom", defaultValue: "Move to room")) {
                ForEach(rooms, id: \.chatRoomID) { room in
                    Button("# \(room.name)") { actions.moveAgent(snapshot.id, room.chatRoomID) }
                }
            }
        }
        Divider()
        Button(String(localized: "chatroom.action.close", defaultValue: "Close"), role: .destructive) { actions.closeWorkspace(snapshot.id) }
    }

    private func beginEdit() { draft = snapshot.title; editing = true }
    private func commit() {
        editing = false
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != snapshot.title { actions.rename(snapshot.id, trimmed) }
    }
}
