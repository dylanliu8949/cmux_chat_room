public import SwiftUI
public import CmuxChatRoomCore
public import CmuxChatRoom

/// The chat channel for one room: windowed exchange list, "Load earlier", a target picker + composer,
/// and a forward sheet. Reads `coordinator.channels[roomID]` (observed) and the room's roster.
///
/// The host app embeds this for a selected `.chatRoom` workspace and supplies ``ChatRoomActions`` for
/// go-to-tab / copy side effects so this package never imports AppKit/cmux.
@MainActor
public struct ChatRoomView: View {
    private let coordinator: RoomsCoordinator
    private let roomID: ChatRoomID
    private let roomName: String
    private let actions: ChatRoomActions

    @State private var roster: [AgentIdentitySnapshot] = []
    @State private var selectedTargets: Set<AgentID> = []
    @State private var composerText: String = ""
    @State private var forwarding: ForwardDraft?

    /// Creates the channel view for `roomID`.
    public init(coordinator: RoomsCoordinator, roomID: ChatRoomID, roomName: String, actions: ChatRoomActions) {
        self.coordinator = coordinator
        self.roomID = roomID
        self.roomName = roomName
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            channelList
            Divider()
            composer
        }
        .task(id: roomID) { await refreshRoster() }
        .sheet(item: $forwarding) { draft in
            ForwardSheet(draft: draft, roster: roster) { note, targets in
                Task {
                    await coordinator.forward(draft.sourceID, quoted: draft.quoted, note: note,
                                              to: targets.map { AgentMention(agentID: $0) }, in: roomID)
                    forwarding = nil
                }
            } onCancel: { forwarding = nil }
        }
    }

    private var exchanges: [Exchange] { coordinator.channels[roomID] ?? [] }

    private var header: some View {
        HStack(spacing: 8) {
            Text("# \(roomName)").font(.system(size: 13, weight: .bold))
            Text(String(localized: "chatroom.agentCount", defaultValue: "\(roster.count) agents"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await refreshRoster() }
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var channelList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await coordinator.loadEarlier(in: roomID) }
                } label: {
                    Text(String(localized: "chatroom.loadEarlier", defaultValue: "Load earlier"))
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

                ForEach(exchanges) { exchange in
                    ExchangeRowView(
                        exchange: exchange,
                        actions: actions,
                        onQuoteIntoComposer: { quoted in
                            composerText = composerText.isEmpty ? "\"\(quoted)\"\n" : composerText + "\n\"\(quoted)\"\n"
                        },
                        onForward: { msgID, body in
                            forwarding = ForwardDraft(sourceID: msgID, quoted: body)
                        }
                    )
                }
            }
            .padding(12)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Target picker: @all + each room agent (scoped to this room).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(title: String(localized: "chatroom.all", defaultValue: "@all"),
                         selected: !roster.isEmpty && selectedTargets.count == roster.count) {
                        if selectedTargets.count == roster.count { selectedTargets.removeAll() }
                        else { selectedTargets = Set(roster.map(\.agentID)) }
                    }
                    ForEach(roster, id: \.agentID) { agent in
                        chip(title: "@\(agent.title)", selected: selectedTargets.contains(agent.agentID)) {
                            if selectedTargets.contains(agent.agentID) { selectedTargets.remove(agent.agentID) }
                            else { selectedTargets.insert(agent.agentID) }
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextEditor(text: $composerText)
                    .font(.system(size: 12))
                    .frame(minHeight: 34, maxHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                Button {
                    send()
                } label: {
                    Text(String(localized: "chatroom.send", defaultValue: "Send"))
                }
                .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedTargets.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
    }

    private func chip(title: String, selected: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.30) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func send() {
        let body = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !selectedTargets.isEmpty else { return }
        let mentions = selectedTargets.map { AgentMention(agentID: $0) }
        composerText = ""
        Task { await coordinator.send(in: roomID, body, to: mentions, origin: .userMention) }
    }

    private func refreshRoster() async {
        roster = await coordinator.roster(inRoom: roomID)
        selectedTargets = selectedTargets.intersection(Set(roster.map(\.agentID)))
    }
}
