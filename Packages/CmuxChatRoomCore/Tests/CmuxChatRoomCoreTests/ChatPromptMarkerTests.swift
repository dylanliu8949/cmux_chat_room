import Foundation
import Testing
@testable import CmuxChatRoomCore

@Suite struct ChatPromptMarkerTests {
    @Test func injectThenExtractRecoversIDAndCleanBody() {
        let id = ChatRequestID(raw: UUID())
        let body = "Please review the auth refactor."
        let injected = ChatPromptMarker.inject(id, into: body)
        let (recovered, cleaned) = ChatPromptMarker.extract(from: injected)
        #expect(recovered == id)
        #expect(cleaned == body)
        #expect(injected.contains(body))
    }

    @Test func multilineBodySurvivesRoundTrip() {
        let id = ChatRequestID(raw: UUID())
        let body = "Line one\n\nLine two with  weird   spacing\n\tindented\nend"
        let injected = ChatPromptMarker.inject(id, into: body)
        let (recovered, cleaned) = ChatPromptMarker.extract(from: injected)
        #expect(recovered == id)
        #expect(cleaned == body)
    }

    @Test func forwardShapedBodyRoundTrips() {
        let id = ChatRequestID(raw: UUID())
        let body = "\"original reply text\nwith newline\"\nmy appended note"
        let injected = ChatPromptMarker.inject(id, into: body)
        let (recovered, cleaned) = ChatPromptMarker.extract(from: injected)
        #expect(recovered == id)
        #expect(cleaned == body)
    }

    @Test func bodyWithNoMarkerExtractsNil() {
        let body = "a direct prompt the user typed in the tab"
        let (recovered, cleaned) = ChatPromptMarker.extract(from: body)
        #expect(recovered == nil)
        #expect(cleaned == body)
    }

    @Test func bodyThatMerelyMentionsTheWordIsNotAFalsePositive() {
        let body = "talk about cmux-chat-request handling in general"
        let (recovered, _) = ChatPromptMarker.extract(from: body)
        #expect(recovered == nil)
    }

    @Test func injectedMarkerIsNotVisibleInBodyText() {
        let id = ChatRequestID(raw: UUID())
        let injected = ChatPromptMarker.inject(id, into: "hello")
        let (_, cleaned) = ChatPromptMarker.extract(from: injected)
        #expect(!cleaned.contains("cmux-chat-request"))
    }
}
