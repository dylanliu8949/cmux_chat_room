import SwiftUI
public import CmuxChatRoomCore

/// One target's row within an exchange: the agent identity + its reply/status, with per-message
/// actions (forward / quote / copy / go-to-tab). Full message text, never collapsed (spec §3.8).
struct ReplyRowView: View {
    let agentID: AgentID
    let identity: AgentIdentitySnapshot?
    let outcome: ReplyOutcome
    let actions: ChatRoomActions
    /// Drop the reply's text into the composer as a quote draft.
    let onQuoteIntoComposer: (String) -> Void
    /// Begin a forward of this reply (opens the forward sheet in the parent).
    let onForward: (MessageID, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(identity?.title ?? "agent")
                    .font(.system(size: 12, weight: .semibold))
                if let identity {
                    Text(subtitle(identity))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(statusLabel).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            switch outcome {
            case .replied(let reply):
                Text(reply.markdownBody)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                actionBar(for: reply)
            case .pending:
                Text(String(localized: "chatroom.reply.waiting", defaultValue: "waiting for reply…"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            case .tabClosed:
                Text(String(localized: "chatroom.reply.tabClosed", defaultValue: "tab closed before replying"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            case .failedToDispatch:
                Text(String(localized: "chatroom.reply.failed", defaultValue: "failed to dispatch"))
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }

    private func subtitle(_ id: AgentIdentitySnapshot) -> String {
        var parts = ["\(id.kind.rawValue) · \(id.cwdDisplay)"]
        if let b = id.branch { parts.append("⎇ \(b)") }
        return parts.joined(separator: "  ")
    }

    @ViewBuilder private func actionBar(for reply: Reply) -> some View {
        HStack(spacing: 12) {
            Button {
                onForward(reply.id, reply.markdownBody)
            } label: { Label(String(localized: "chatroom.action.forward", defaultValue: "Forward"), systemImage: "arrowshape.turn.up.right") }
            Button {
                onQuoteIntoComposer(reply.markdownBody)
            } label: { Label(String(localized: "chatroom.action.quote", defaultValue: "Quote"), systemImage: "text.quote") }
            Button {
                actions.copyText(reply.markdownBody)
            } label: { Label(String(localized: "chatroom.action.copy", defaultValue: "Copy"), systemImage: "doc.on.doc") }
            Button {
                actions.goToAgent(agentID)
            } label: { Label(String(localized: "chatroom.action.gotoTab", defaultValue: "Go to tab"), systemImage: "arrow.up.right.square") }
            Spacer()
        }
        .labelStyle(.titleAndIcon)
        .font(.system(size: 10))
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var statusColor: Color {
        switch outcome {
        case .replied: return .green
        case .pending: return .secondary
        case .tabClosed: return .secondary
        case .failedToDispatch: return .orange
        }
    }

    private var statusLabel: String {
        switch outcome {
        case .replied: return String(localized: "chatroom.status.replied", defaultValue: "replied")
        case .pending: return String(localized: "chatroom.status.pending", defaultValue: "pending")
        case .tabClosed: return String(localized: "chatroom.status.tabClosed", defaultValue: "closed")
        case .failedToDispatch: return String(localized: "chatroom.status.failed", defaultValue: "failed")
        }
    }
}
