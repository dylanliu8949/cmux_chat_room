import Foundation
public import CmuxChatRoomCore

/// In-progress forward of a reply: the source message and its quoted body.
struct ForwardDraft: Identifiable {
    let id = UUID()
    let sourceID: MessageID
    let quoted: String
}
