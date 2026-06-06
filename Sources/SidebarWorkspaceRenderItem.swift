import Foundation

/// One drawable item in the workspace sidebar.
@MainActor
enum SidebarWorkspaceRenderItem {
    case groupHeader(WorkspaceGroup, memberWorkspaceIds: [UUID])
    case workspace(Workspace)
    /// A plain text section/sub-section header used by the chat-room two-section sidebar.
    case sectionHeader(String)

    var id: String {
        switch self {
        case .groupHeader(let group, _):
            return "group.\(group.id.uuidString)"
        case .workspace(let workspace):
            return "workspace.\(workspace.id.uuidString)"
        case .sectionHeader(let title):
            return "section.\(title)"
        }
    }

    /// Title for the chat-rooms section header (also used to wire its `+` action).
    static let chatRoomsSectionTitle = String(localized: "sidebar.section.chatRooms", defaultValue: "Chat rooms")
    /// Title for the agents section header (also used to wire its `+` action).
    static let agentsSectionTitle = String(localized: "sidebar.section.agents", defaultValue: "Agents")

    /// Two flat sections: chat rooms on top, then all agents. Each section header carries a `+` to
    /// create a new room / agent. No "ungrouped" and no per-room sub-grouping (membership is still
    /// tracked by `roomID` internally for `@`-scoping).
    static func chatRoomRenderItems(tabs: [Workspace]) -> [SidebarWorkspaceRenderItem] {
        var items: [SidebarWorkspaceRenderItem] = []
        items.append(.sectionHeader(chatRoomsSectionTitle))
        for room in tabs where room.workspaceRole == .chatRoom { items.append(.workspace(room)) }
        items.append(.sectionHeader(agentsSectionTitle))
        for agent in tabs where agent.workspaceRole == .agent { items.append(.workspace(agent)) }
        return items
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
