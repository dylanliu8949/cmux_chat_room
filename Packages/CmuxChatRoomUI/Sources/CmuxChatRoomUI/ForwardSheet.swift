import SwiftUI
public import CmuxChatRoomCore

/// Forward composer: shows the quoted original, lets the user add a note and pick targets, then sends.
struct ForwardSheet: View {
    let draft: ForwardDraft
    let roster: [AgentIdentitySnapshot]
    let onSend: (_ note: String, _ targets: [AgentID]) -> Void
    let onCancel: () -> Void

    @State private var note: String = ""
    @State private var selected: Set<AgentID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "chatroom.forward.title", defaultValue: "Forward message"))
                .font(.headline)
            ScrollView {
                Text("\"\(draft.quoted)\"")
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))

            Text(String(localized: "chatroom.forward.note", defaultValue: "Add a note"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            TextEditor(text: $note)
                .font(.system(size: 12))
                .frame(height: 60)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            Text(String(localized: "chatroom.forward.to", defaultValue: "Send to"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(roster, id: \.agentID) { agent in
                        Button {
                            if selected.contains(agent.agentID) { selected.remove(agent.agentID) }
                            else { selected.insert(agent.agentID) }
                        } label: {
                            Text("@\(agent.title)").font(.system(size: 11))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(selected.contains(agent.agentID) ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()
                Button(String(localized: "chatroom.cancel", defaultValue: "Cancel"), action: onCancel)
                Button(String(localized: "chatroom.forward.send", defaultValue: "Forward")) {
                    onSend(note, Array(selected))
                }
                .disabled(selected.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}
