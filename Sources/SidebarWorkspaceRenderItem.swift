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

    /// Two-section ordering for the chat room: chat-room workspaces on top, then agent workspaces
    /// grouped under their room (membership by `roomID`). Net-new, not the flat group renderer.
    static func chatRoomRenderItems(tabs: [Workspace]) -> [SidebarWorkspaceRenderItem] {
        let rooms = tabs.filter { $0.workspaceRole == .chatRoom }
        let agents = tabs.filter { $0.workspaceRole == .agent }
        guard !rooms.isEmpty || !agents.isEmpty else { return [] }

        var items: [SidebarWorkspaceRenderItem] = []
        items.append(.sectionHeader(String(localized: "sidebar.section.chatRooms", defaultValue: "Chat rooms")))
        for room in rooms { items.append(.workspace(room)) }

        items.append(.sectionHeader(String(localized: "sidebar.section.agents", defaultValue: "Agents")))
        var placed: Set<UUID> = []
        for room in rooms {
            guard let rid = room.chatRoomID else { continue }
            let members = agents.filter { $0.roomID == rid }
            guard !members.isEmpty else { continue }
            items.append(.sectionHeader(room.roomName ?? room.title))
            for agent in members {
                items.append(.workspace(agent))
                placed.insert(agent.id)
            }
        }
        let orphans = agents.filter { !placed.contains($0.id) }
        if !orphans.isEmpty {
            items.append(.sectionHeader(String(localized: "sidebar.section.ungrouped", defaultValue: "Ungrouped")))
            for agent in orphans { items.append(.workspace(agent)) }
        }
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
