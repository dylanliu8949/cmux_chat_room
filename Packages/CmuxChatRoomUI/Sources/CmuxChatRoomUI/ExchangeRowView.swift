import SwiftUI
import CmuxChatRoomCore

/// One exchange (mockup exchange-status.png / layout-choice.png): the outgoing prompt header with an
/// "N / M replied" pill, then each target's reply row grouped beneath a green rail.
struct ExchangeRowView: View {
    let exchange: Exchange
    /// Live lifecycle per agent, for in-flight running / needs-input visibility.
    let lifecycle: [AgentID: AgentLifecycle]
    let actions: ChatRoomActions
    let onForward: (MessageID, String) -> Void
    let onQuoteIntoComposer: (String) -> Void
    let onReplyDisplayHeightChange: (MessageID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Outgoing prompt header.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(localized: "chatroom.you", defaultValue: "you"))
                    .font(.system(size: 13, weight: .semibold))
                Text("→").foregroundStyle(.secondary)
                Text(targetSummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                if case .forward = exchange.prompt.origin {
                    Text(String(localized: "chatroom.forwarded", defaultValue: "(forwarded)"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(progressLabel)
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Text(exchange.prompt.bodyText)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Replies, grouped beneath a green rail (mockup).
            VStack(alignment: .leading, spacing: 8) {
                ForEach(exchange.prompt.targets, id: \.agentID) { target in
                    ReplyRowView(
                        agentID: target.agentID,
                        identity: target,
                        outcome: exchange.outcomes[target.agentID] ?? .pending,
                        liveState: lifecycle[target.agentID] ?? .unknown,
                        actions: actions,
                        onForward: onForward,
                        onQuoteIntoComposer: onQuoteIntoComposer,
                        onDisplayHeightChange: onReplyDisplayHeightChange
                    )
                }
            }
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.green.opacity(0.5)).frame(width: 2)
            }
        }
    }

    private var targetSummary: String {
        exchange.prompt.targets.map { "@\($0.title)" }.joined(separator: ", ")
    }

    private var progressLabel: String {
        let replied = exchange.outcomes.values.filter { if case .replied = $0 { return true } else { return false } }.count
        return String(localized: "chatroom.progress",
                      defaultValue: "\(replied) / \(exchange.prompt.targets.count) replied")
    }
}
