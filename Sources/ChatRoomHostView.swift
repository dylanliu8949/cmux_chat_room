import AppKit
import SwiftUI
import CmuxChatRoomCore
import CmuxChatRoom
import CmuxChatRoomUI

/// Hosts the package ``ChatRoomView`` in the content area for a selected `.chatRoom` workspace,
/// wiring go-to-tab / copy side effects to AppKit + `TabManager`.
struct ChatRoomHostView: View {
    let workspace: Workspace
    let tabManager: TabManager

    var body: some View {
        if let controller = ChatRoomController.shared, let rid = workspace.chatRoomID {
            ChatRoomView(
                coordinator: controller.coordinator,
                roomID: ChatRoomID(raw: rid),
                roomName: workspace.roomName ?? workspace.title,
                actions: ChatRoomActions(
                    goToAgent: { agentID in
                        if let ws = tabManager.agentWorkspace(id: agentID.raw) {
                            tabManager.selectTab(ws)
                        }
                    },
                    copyText: { text in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                )
            )
            .onAppear { controller.clearBadge(rid) }
        } else {
            Text(String(localized: "chatroom.unavailable", defaultValue: "Chat room unavailable"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Shown in the content area when there are no chat rooms yet (fresh start) — prompts the user to
/// create their first room from the sidebar `+`.
struct ChatRoomEmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(String(localized: "chatroom.empty.title", defaultValue: "No chat rooms yet"))
                .font(.system(size: 15, weight: .semibold))
            Text(String(localized: "chatroom.empty.subtitle",
                        defaultValue: "Click + next to “CHAT ROOMS” in the sidebar to create your first room, then add agents to it."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(String(localized: "chatroom.empty.create", defaultValue: "Create a chat room")) {
                ChatRoomController.shared?.promptNewRoom()
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A chat-room sidebar section/sub-section header with an optional `+` action.
struct ChatRoomSidebarSectionHeader: View {
    let title: String
    let onAdd: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(localized: "sidebar.section.add", defaultValue: "Add"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}
