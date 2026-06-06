import SwiftUI
public import CmuxChatRoomCore

/// One exchange: the outgoing prompt followed by each target's reply row, plus an N/M progress line.
struct ExchangeRowView: View {
    let exchange: Exchange
    let actions: ChatRoomActions
    let onQuoteIntoComposer: (String) -> Void
    let onForward: (MessageID, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Outgoing prompt.
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(String(localized: "chatroom.you", defaultValue: "you"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(targetSummary).font(.system(size: 10)).foregroundStyle(.secondary)
                    if case .forward = exchange.prompt.origin {
                        Text(String(localized: "chatroom.forwarded", defaultValue: "(forwarded)"))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(progressLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text(exchange.prompt.bodyText)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.10)))

            // Replies, in target order.
            ForEach(exchange.prompt.targets, id: \.agentID) { target in
                ReplyRowView(
                    agentID: target.agentID,
                    identity: target,
                    outcome: exchange.outcomes[target.agentID] ?? .pending,
                    actions: actions,
                    onQuoteIntoComposer: onQuoteIntoComposer,
                    onForward: onForward
                )
                .padding(.leading, 14)
            }
        }
    }

    private var targetSummary: String {
        "→ " + exchange.prompt.targets.map(\.title).joined(separator: ", ")
    }

    private var progressLabel: String {
        let replied = exchange.outcomes.values.filter { if case .replied = $0 { return true } else { return false } }.count
        return "\(replied)/\(exchange.prompt.targets.count)"
    }
}
