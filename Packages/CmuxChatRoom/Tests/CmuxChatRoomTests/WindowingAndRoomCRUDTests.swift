import Foundation
import Testing
@testable import CmuxChatRoom
import CmuxChatRoomCore

@MainActor
@Suite struct WindowingAndRoomCRUDTests {
    @Test func roomCRUDForwardsToManagingSeam() async {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist)
        let id = await coord.createRoom(name: "feature-auth")
        await coord.renameRoom(id, to: "feature-auth-2")
        await coord.closeRoom(id)
        #expect(await rooms.created == ["feature-auth"])
        #expect(await rooms.renamed.contains(where: { $0.0 == id && $0.1 == "feature-auth-2" }))
        #expect(await rooms.closeRequested.contains(id))
        await rooms.setActive(id)
        #expect(await coord.activeRoomID() == id)
    }

    @Test func loadEarlierPagesOlderExchangesRespectingWindow() async {
        let rooms = FakeRoomWorkspace(); let roster = FakeRoster(); let life = FakeLifecycle()
        let inj = FakeInjector(); let notif = FakeNotifier(); let hist = InMemoryHistoryStore()
        let room = ChatRoomID(raw: UUID())
        for i in 0..<5 {
            let ex = ExchangeID(raw: UUID())
            let p = OutgoingPrompt(exchangeID: ex, roomID: room, origin: .userMention,
                                   bodyText: "m\(i)", targets: [], sentAt: Date(timeIntervalSince1970: Double(i)))
            await hist.append(Exchange(prompt: p, outcomes: [:]), in: room)
        }
        let coord = RoomsCoordinator(roomsReading: rooms, roomsManaging: rooms, roster: roster,
                                     lifecycle: life, injector: inj, notifier: notif, history: hist,
                                     windowSize: 2)
        await coord.loadEarlier(in: room)
        #expect((coord.channels[room] ?? []).map(\.prompt.bodyText) == ["m3", "m4"])
        await coord.loadEarlier(in: room)
        #expect((coord.channels[room] ?? []).map(\.prompt.bodyText) == ["m1", "m2", "m3", "m4"])
    }
}
