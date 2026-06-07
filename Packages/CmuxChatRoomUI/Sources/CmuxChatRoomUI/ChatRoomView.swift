public import SwiftUI
public import CmuxChatRoomCore
public import CmuxChatRoom

/// The chat channel for one room: persisted recent exchanges, "Load earlier", an `@`-mention
/// composer, and a forward sheet. Reads `coordinator.channels[roomID]` (observed) and re-fetches
/// the live lifecycle (`coordinator.lifecycleVersion`) for in-flight running / needs-input visibility.
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
    @State private var forwarding: ForwardDraft?
    /// Live lifecycle per agent, re-fetched on `coordinator.lifecycleVersion` (spec §3.6).
    @State private var lifecycleByAgent: [AgentID: AgentLifecycle] = [:]
    /// Bumped to force the composer to rebuild its roster-derived state fresh on open.
    @State private var composerEpoch = 0
    /// Quote-into-composer seed (§3.7): set by a reply's Quote action, consumed by the composer.
    @State private var composerSeed: String?

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
            MentionComposer(roster: roster, seed: $composerSeed) { body, targets in
                Task {
                    await coordinator.send(in: roomID, body,
                                           to: targets.map { AgentMention(agentID: $0) }, origin: .userMention)
                }
            }
            .id(composerEpoch)
        }
        .task(id: roomID) { await refreshAll() }
        .onChange(of: coordinator.lifecycleVersion) { Task { await refreshLifecycle() } }
        .onChange(of: exchanges.count) { Task { await refreshLifecycle() } }
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
                composerEpoch += 1
                Task { await refreshAll() }
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(String(localized: "chatroom.refresh", defaultValue: "Refresh roster"))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var channelList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
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
                            lifecycle: lifecycleByAgent,
                            actions: actions,
                            onForward: { msgID, quoted in forwarding = ForwardDraft(sourceID: msgID, quoted: quoted) },
                            onQuoteIntoComposer: { quoted in composerSeed = quoted },
                            onReplyDisplayHeightChange: { replyID in
                                Task { @MainActor in
                                    await Task.yield()
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        proxy.scrollTo(replyID, anchor: .top)
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(12)
            }
        }
    }

    private func refreshAll() async {
        roster = await coordinator.roster(inRoom: roomID)
        if exchanges.isEmpty {
            await coordinator.loadEarlier(in: roomID)
        }
        await refreshLifecycle()
    }

    private func refreshLifecycle() async {
        lifecycleByAgent = await coordinator.lifecycleSnapshot()
    }
}
