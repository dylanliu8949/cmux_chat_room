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
