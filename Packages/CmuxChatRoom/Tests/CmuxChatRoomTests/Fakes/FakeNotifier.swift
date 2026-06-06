import Foundation
import CmuxChatRoomCore

/// Fake notifier recording which rooms were badged.
actor FakeNotifier: ChatNotifying {
    private(set) var badged: [ChatRoomID] = []
    func notifyRoomCompletion(_ room: ChatRoomID) async { badged.append(room) }
}
