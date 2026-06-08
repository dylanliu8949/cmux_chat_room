import AppKit
import ObjectiveC.runtime
import SwiftUI
import WebKit
import XCTest
import CmuxUpdater

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class FileDropOverlayViewTests: XCTestCase {
    private func makeContentViewWindow(windowId: UUID = UUID()) -> NSWindow {
        _ = NSApplication.shared

        let root = ContentView(updateViewModel: UpdateStateModel(), windowId: windowId)
            .environmentObject(TabManager())
            .environmentObject(TerminalNotificationStore.shared)
            .environmentObject(SidebarState())
            .environmentObject(SidebarSelectionState())
            .environmentObject(FileExplorerState())
            .environmentObject(CmuxConfigStore())

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = MainWindowHostingView(rootView: root)
        return window
    }

    private func fileDropOverlays(in root: NSView?) -> [FileDropOverlayView] {
        guard let root else { return [] }

        var overlays: [FileDropOverlayView] = []
        if let overlay = root as? FileDropOverlayView {
            overlays.append(overlay)
        }
        for subview in root.subviews {
            overlays.append(contentsOf: fileDropOverlays(in: subview))
        }
        return overlays
    }

    private func realizeWindowLayout(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func testContentViewInstallsSingleFileDropOverlayAcrossRepeatedLayouts() {
        let window = makeContentViewWindow()
        defer {
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
            window.orderOut(nil)
        }

        realizeWindowLayout(window)
        realizeWindowLayout(window)
        realizeWindowLayout(window)

        guard let themeFrame = window.contentView?.superview else {
            XCTFail("Expected theme frame")
            return
        }

        let overlays = fileDropOverlays(in: themeFrame)
        XCTAssertEqual(
            overlays.count,
            1,
            "ContentView should install exactly one FileDropOverlayView even after repeated layout passes"
        )
        XCTAssertTrue(
            (objc_getAssociatedObject(window, &fileDropOverlayKey) as? FileDropOverlayView) === overlays.first,
            "The window-associated file-drop overlay should match the single installed view"
        )
    }

}
