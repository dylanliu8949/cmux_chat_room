import SwiftUI
import CmuxChatRoomCore

/// One target's row within an exchange (mockup message-and-forward.png / exchange-status.png): the
/// agent identity (green name + ~cwd · branch), then either its full reply with per-message actions
/// (forward / quote / copy / go-to-tab), or — while pending — a live status line driven by lifecycle
/// (`⟳ still working…` / amber `⚠ needs input — go to tab →`). Full message text, never collapsed (§3.8).
struct ReplyRowView: View {
    let agentID: AgentID
    let identity: AgentIdentitySnapshot?
    let outcome: ReplyOutcome
    /// Live lifecycle of this agent (for the pending state).
    let liveState: AgentLifecycle
    let actions: ChatRoomActions
    let onForward: (MessageID, String) -> Void
    let onQuoteIntoComposer: (String) -> Void

    private var hasReplied: Bool { if case .replied = outcome { return true } else { return false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Identity line: green name + ~cwd · branch (snapshotted at send time).
            HStack(spacing: 6) {
                Text(identity?.title ?? "agent")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(hasReplied ? Color.green : Color.primary)
                if let identity {
                    Text(subtitle(identity))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch outcome {
        case .replied(let reply):
            Text(reply.markdownBody)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            actionBar(for: reply)
        case .pending:
            pendingStatus
        case .tabClosed:
            Text(String(localized: "chatroom.reply.tabClosed", defaultValue: "tab closed before replying"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        case .failedToDispatch:
            Text(String(localized: "chatroom.reply.failed", defaultValue: "failed to dispatch"))
                .font(.system(size: 11)).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var pendingStatus: some View {
        switch liveState {
        case .needsInput:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                Text(String(localized: "chatroom.reply.needsInput",
                            defaultValue: "needs input — waiting on a prompt in its tab."))
                    .font(.system(size: 11))
                Button(String(localized: "chatroom.reply.goToTab", defaultValue: "go to tab →")) {
                    actions.goToAgent(agentID)
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).underline()
            }
            .foregroundStyle(.orange)
        case .running:
            HStack(spacing: 4) {
                Image(systemName: "circle.dotted").font(.system(size: 10))
                Text(String(localized: "chatroom.reply.working", defaultValue: "still working…"))
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
        case .idle, .unknown:
            Text(String(localized: "chatroom.reply.waiting", defaultValue: "waiting for reply…"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func subtitle(_ id: AgentIdentitySnapshot) -> String {
        var s = id.cwdDisplay
        if let b = id.branch { s += " · \(b)" }
        return s
    }

    @ViewBuilder private func actionBar(for reply: Reply) -> some View {
        HStack(spacing: 12) {
            Button { onForward(reply.id, reply.markdownBody) } label: {
                Label(String(localized: "chatroom.action.forward", defaultValue: "Forward"), systemImage: "arrowshape.turn.up.right")
            }
            Button { onQuoteIntoComposer(reply.markdownBody) } label: {
                Label(String(localized: "chatroom.action.quote", defaultValue: "Quote"), systemImage: "text.quote")
            }
            Button { actions.copyText(reply.markdownBody) } label: {
                Label(String(localized: "chatroom.action.copy", defaultValue: "Copy"), systemImage: "doc.on.doc")
            }
            Button { actions.goToAgent(agentID) } label: {
                Label(String(localized: "chatroom.action.gotoTab", defaultValue: "Go to tab"), systemImage: "arrow.up.right.square")
            }
            Spacer()
        }
        .labelStyle(.titleAndIcon)
        .font(.system(size: 10))
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
