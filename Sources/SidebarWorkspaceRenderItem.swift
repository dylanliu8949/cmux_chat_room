import Foundation
import CmuxChatRoomCore

/// One drawable item in the workspace sidebar.
@MainActor
enum SidebarWorkspaceRenderItem {
    case groupHeader(WorkspaceGroup, memberWorkspaceIds: [UUID])
    case workspace(Workspace)
    /// A plain text section header (top-level: "Chat rooms" / "Agents").
    case sectionHeader(String)
    /// A chat-room channel row (top section).
    case roomRow(ChatRoomRowSnapshot)
    /// An agent row nested under its room (three-line + status badge).
    case agentRow(ChatAgentRowSnapshot)

    var id: String {
        switch self {
        case .groupHeader(let group, _):
            return "group.\(group.id.uuidString)"
        case .workspace(let workspace):
            return "workspace.\(workspace.id.uuidString)"
        case .sectionHeader(let title):
            return "section.\(title)"
        case .roomRow(let s):
            return "room.\(s.id.uuidString)"
        case .agentRow(let s):
            return "agent.\(s.id.uuidString)"
        }
    }

    /// Title for the chat-rooms section header (also used to wire its `+` action).
    static let chatRoomsSectionTitle = String(localized: "sidebar.section.chatRooms", defaultValue: "Chat rooms")
    /// Title for the agents section header (also used to wire its `+` action).
    static let agentsSectionTitle = String(localized: "sidebar.section.agents", defaultValue: "Agents")
    /// Stable sentinel id for the "unassigned" sub-header (not a real room; no add/collapse controls).
    static let unassignedSentinelID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// One unified list: a "CHAT ROOMS" header (its `+` creates a room), then each chat room as a
    /// colored `#` header row (its `+` adds an agent into that room) with its **agents nested directly
    /// beneath it** as three-line rows + live status badge. No separate "Agents" section. All rows are
    /// value snapshots (snapshot-boundary safe).
    static func chatRoomRenderItems(
        tabs: [Workspace],
        selectedWorkspaceID: UUID?,
        badgedRoomIDs: Set<UUID>
    ) -> [SidebarWorkspaceRenderItem] {
        let rooms = tabs.filter { $0.workspaceRole == .chatRoom }
        // Only real agents (a resolvable `AgentKind`) are shown. This app has **no non-agent
        // terminals**; legacy/kindless terminal tabs (e.g. migrated from a pre-fork session) are
        // never rendered as agents.
        let agents = tabs.filter {
            $0.workspaceRole == .agent && $0.agentKindRaw.flatMap(AgentKind.init(rawValue:)) != nil
        }

        var items: [SidebarWorkspaceRenderItem] = [.sectionHeader(chatRoomsSectionTitle)]
        for room in rooms {
            guard let crid = room.chatRoomID else { continue }
            items.append(.roomRow(ChatRoomRowSnapshot(
                id: room.id,
                chatRoomID: crid,
                name: room.roomName ?? room.title,
                colorHex: room.customColor,
                isSelected: room.id == selectedWorkspaceID,
                hasUnread: badgedRoomIDs.contains(crid)
            )))
            for agent in agents where agent.roomID == crid {
                items.append(.agentRow(agentSnapshot(agent, selectedWorkspaceID: selectedWorkspaceID)))
            }
        }
        return items
    }

    /// Builds an agent row snapshot, reading lifecycle from the store *here* (parent scope) so the row
    /// itself never holds a store reference.
    private static func agentSnapshot(_ agent: Workspace, selectedWorkspaceID: UUID?) -> ChatAgentRowSnapshot {
        let supported = agent.agentKindRaw.flatMap(AgentKind.init(rawValue:)) != nil
        return ChatAgentRowSnapshot(
            id: agent.id,
            title: agent.customTitle ?? agent.title,
            cwdDisplay: abbreviateHomePath(agent.currentDirectory),
            branch: agent.gitBranch?.branch,
            lifecycle: AppLifecycleSeam.aggregateLifecycle(for: agent),
            isSelected: agent.id == selectedWorkspaceID,
            isSupported: supported
        )
    }

    /// `~`-abbreviates a path for the three-line agent row.
    private static func abbreviateHomePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
    static func renderItems(
        tabs: [Workspace],
        groupsById: [UUID: WorkspaceGroup]
    ) -> [SidebarWorkspaceRenderItem] {
        guard !tabs.isEmpty else { return [] }
        var memberWorkspaceIdsByGroupId: [UUID: [UUID]] = [:]
        for tab in tabs {
            if let gid = tab.groupId {
                memberWorkspaceIdsByGroupId[gid, default: []].append(tab.id)
            }
        }
        var items: [SidebarWorkspaceRenderItem] = []
        items.reserveCapacity(tabs.count + groupsById.count)
        var lastEmittedGroupId: UUID? = nil
        var emittedHeaders: Set<UUID> = []
        var collapsedByGroupId: [UUID: Bool] = [:]
        var skipChildrenUntilNextGroup = false
        for tab in tabs {
            let groupId = tab.groupId
            if groupId != lastEmittedGroupId {
                lastEmittedGroupId = groupId
                skipChildrenUntilNextGroup = false
                if let groupId, let group = groupsById[groupId] {
                    if !emittedHeaders.contains(groupId) {
                        let memberWorkspaceIds = memberWorkspaceIdsByGroupId[groupId] ?? []
                        items.append(.groupHeader(group, memberWorkspaceIds: memberWorkspaceIds))
                        emittedHeaders.insert(groupId)
                        collapsedByGroupId[groupId] = group.isCollapsed
                    }
                    // If legacy reorder paths ever leave a group's members in
                    // two runs, keep honoring the same collapse decision.
                    skipChildrenUntilNextGroup = collapsedByGroupId[groupId] ?? false
                }
            }
            // Anchor workspaces are represented exclusively by the group header.
            if let groupId, let group = groupsById[groupId], group.anchorWorkspaceId == tab.id {
                continue
            }
            if groupId == nil || !skipChildrenUntilNextGroup {
                items.append(.workspace(tab))
            }
        }
        return items
    }
}
