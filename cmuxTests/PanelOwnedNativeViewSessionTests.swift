import AppKit
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class PanelOwnedNativeViewSessionTests: XCTestCase {
    private final class ProbeView: NSView {
        var isClosed = false
        var configureCount = 0
    }

    func testUpdateAfterCloseDoesNotReAdoptClosedNativeView() {
        var makeCount = 0
        let session = PanelOwnedNativeViewSession<ProbeView>(
            makeView: {
                makeCount += 1
                return ProbeView(frame: .zero)
            },
            closeView: { view in
                view.isClosed = true
                view.removeFromSuperview()
            }
        )

        let initialView = session.view { view in
            XCTAssertFalse(view.isClosed)
            view.configureCount += 1
        }

        XCTAssertEqual(makeCount, 1)
        XCTAssertEqual(initialView.configureCount, 1)

        session.close()

        XCTAssertTrue(initialView.isClosed)

        session.update(initialView) { view in
            XCTFail("Closed native views must not be re-adopted or configured after the panel session closes")
            view.configureCount += 1
        }

        XCTAssertEqual(initialView.configureCount, 1)

        let replacementView = session.view { view in
            XCTAssertFalse(view.isClosed)
            view.configureCount += 1
        }

        XCTAssertFalse(replacementView === initialView)
        XCTAssertEqual(replacementView.configureCount, 1)
        XCTAssertEqual(makeCount, 2)
    }
}
