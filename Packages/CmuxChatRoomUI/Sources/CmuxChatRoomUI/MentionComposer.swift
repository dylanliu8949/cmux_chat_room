import SwiftUI
import CmuxChatRoomCore

/// The channel composer (spec §3.10): pick targets by typing `@name` against an autocomplete dropdown
/// whose rows show **name · kind · ~cwd · branch** (so duplicate titles / same-repo-different-branch
/// agents are distinguishable), plus an `@all` shortcut, then write the message body and send.
///
/// Selection stores a stable ``AgentID`` (never the display string). The dropdown is rebuilt from the
/// passed-in `roster` (the host refreshes it fresh on open, scoped to the active room).
struct MentionComposer: View {
    /// Live, room-scoped roster (the mentionable set).
    let roster: [AgentIdentitySnapshot]
    /// Text to seed into the body (quote-into-composer, §3.7). When set, it is appended and cleared.
    @Binding var seed: String?
    /// Sends `body` to the chosen targets.
    let onSend: (_ body: String, _ targets: [AgentID]) -> Void

    @State private var selected: [AgentID] = []
    @State private var query: String = ""
    @State private var messageText: String = ""
    @FocusState private var mentionFocused: Bool

    private var byID: [AgentID: AgentIdentitySnapshot] {
        Dictionary(roster.map { ($0.agentID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Roster rows matching the current `@`-query, excluding already-selected agents.
    private var matches: [AgentIdentitySnapshot] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return roster.filter { agent in
            !selected.contains(agent.agentID)
            && (q.isEmpty || agent.title.lowercased().contains(q))
        }
    }

    private var canSend: Bool {
        !selected.isEmpty && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            targetsRow
            if mentionFocused, !matches.isEmpty {
                autocomplete
            }
            VStack(alignment: .trailing, spacing: 6) {
                MentionComposerTextEditor(text: $messageText) { send() }
                    .frame(minHeight: 34, maxHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                Button(String(localized: "chatroom.send", defaultValue: "Send")) { _ = send() }
                    .disabled(!canSend)
            }
        }
        .padding(12)
        .onChange(of: seed) {
            guard let s = seed else { return }
            messageText = messageText.isEmpty ? "\"\(s)\"\n" : messageText + "\n\"\(s)\"\n"
            seed = nil
        }
    }

    // MARK: Targets row (chips + @-field + @all)

    private var targetsRow: some View {
        HStack(spacing: 6) {
            Text(String(localized: "chatroom.to", defaultValue: "to:"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            // @all shortcut.
            chip(title: String(localized: "chatroom.all", defaultValue: "@all"),
                 selected: !roster.isEmpty && selected.count == roster.count) {
                selected = (selected.count == roster.count) ? [] : roster.map(\.agentID)
            }
            // Selected target chips (removable).
            ForEach(selected, id: \.self) { id in
                if let agent = byID[id] {
                    chip(title: "@\(agent.title)", selected: true) { selected.removeAll { $0 == id } }
                }
            }
            // Typed @-mention field.
            TextField(String(localized: "chatroom.mention.hint", defaultValue: "@…"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(minWidth: 60)
                .focused($mentionFocused)
                .onSubmit { if let first = matches.first { add(first.agentID) } }
            Spacer(minLength: 0)
        }
    }

    private var autocomplete: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(matches.prefix(8), id: \.agentID) { agent in
                Button { add(agent.agentID) } label: { row(agent) }
                    .buttonStyle(.plain)
                if agent.agentID != matches.prefix(8).last?.agentID { Divider() }
            }
        }
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
    }

    /// One autocomplete row: name + kind + ~cwd + branch (§3.10 disambiguation).
    private func row(_ agent: AgentIdentitySnapshot) -> some View {
        HStack(spacing: 6) {
            Text(agent.title).font(.system(size: 12, weight: .medium))
            Text(agent.kind.rawValue).font(.system(size: 10)).foregroundStyle(.secondary)
            Text("· \(agent.cwdDisplay)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            if let b = agent.branch {
                Text("⎇ \(b)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func chip(title: String, selected: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.30) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func add(_ id: AgentID) {
        if !selected.contains(id) { selected.append(id) }
        query = ""
    }

    @discardableResult
    private func send() -> Bool {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty, !trimmed.isEmpty else { return false }
        onSend(trimmed, selected)
        messageText = ""
        return true
    }
}
