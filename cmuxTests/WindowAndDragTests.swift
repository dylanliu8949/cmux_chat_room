import XCTest
import AppKit
import Carbon.HIToolbox
import Darwin
import PDFKit
import Testing
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import ObjectiveC.runtime
@testable import Bonsplit
import UserNotifications

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

private final class FakeBonsplitTabItemRegionView: NSView, BonsplitTabItemHitRegionProviding {
    nonisolated(unsafe) var tabFrames: [CGRect] = []

    deinit {}

    nonisolated func containsBonsplitTabItemHit(localPoint: NSPoint) -> Bool {
        tabFrames.contains { $0.contains(localPoint) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
final class WindowGlassEffectTests: XCTestCase {
    func testRemoveRestoresOriginalContentHierarchy() {
        _ = NSApplication.shared

        let originalContentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        let window = NSWindow(
            contentRect: originalContentView.bounds,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = originalContentView

        WindowGlassEffect.apply(to: window, tintColor: .systemBlue)

        if WindowGlassEffect.isAvailable {
            XCTAssertFalse(window.contentView === originalContentView)
            XCTAssertTrue(WindowGlassEffect.originalContentView(for: window) === originalContentView)
            XCTAssertTrue(originalContentView.superview === WindowGlassEffect.foregroundContainer(for: window))
            XCTAssertNotNil(WindowGlassEffect.portalInstallationTarget(for: window))
        } else {
            XCTAssertTrue(window.contentView === originalContentView)
            XCTAssertNil(WindowGlassEffect.originalContentView(for: window))
            XCTAssertNil(WindowGlassEffect.foregroundContainer(for: window))
            XCTAssertNil(WindowGlassEffect.portalInstallationTarget(for: window))
        }
        XCTAssertTrue(Self.windowContainsGlassBackground(window))

        WindowGlassEffect.remove(from: window)

        XCTAssertTrue(window.contentView === originalContentView)
        XCTAssertNil(WindowGlassEffect.foregroundContainer(for: window))
        XCTAssertNil(WindowGlassEffect.originalContentView(for: window))
        XCTAssertFalse(Self.windowContainsGlassBackground(window))
    }

    func testNativeGlassTintFollowsWindowKeyNotifications() throws {
        guard WindowGlassEffect.isAvailable else {
            throw XCTSkip("NSGlassEffectView is unavailable on this macOS version")
        }
        _ = NSApplication.shared

        let originalContentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        let window = NSWindow(
            contentRect: originalContentView.bounds,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = originalContentView

        WindowGlassEffect.apply(to: window, tintColor: .black, style: .clear)

        guard let backgroundView = Self.glassBackgroundView(in: window.contentView),
              let tintOverlay = backgroundView.subviews.last else {
            XCTFail("Expected glass background tint overlay")
            return
        }

        XCTAssertGreaterThan(tintOverlay.alphaValue, 0)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(tintOverlay.alphaValue, 0, accuracy: 0.001)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertGreaterThan(tintOverlay.alphaValue, 0)
    }

    private static func windowContainsGlassBackground(_ window: NSWindow) -> Bool {
        guard let contentView = window.contentView else { return false }
        let root = contentView.superview ?? contentView
        return glassBackgroundView(in: root) != nil
    }

    private static func glassBackgroundView(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view.identifier == WindowGlassEffect.backgroundViewIdentifier {
            return view
        }
        return view.subviews.lazy.compactMap(glassBackgroundView(in:)).first
    }
}

@MainActor
final class WindowAccessorTests: XCTestCase {
    func testSameWindowDedupeAllowsRefreshIDChanges() {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let coordinator = WindowAccessor.Coordinator()

        XCTAssertTrue(coordinator.shouldInvoke(window: window, dedupeByWindow: true, refreshID: "glass-off"))
        XCTAssertFalse(coordinator.shouldInvoke(window: window, dedupeByWindow: true, refreshID: "glass-off"))
        XCTAssertTrue(coordinator.shouldInvoke(window: window, dedupeByWindow: true, refreshID: "glass-clear"))
        XCTAssertFalse(coordinator.shouldInvoke(window: window, dedupeByWindow: true, refreshID: "glass-clear"))
    }

    func testDedupeDisabledAlwaysInvokesForSameWindow() {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let coordinator = WindowAccessor.Coordinator()

        XCTAssertTrue(coordinator.shouldInvoke(window: window, dedupeByWindow: false, refreshID: "same"))
        XCTAssertTrue(coordinator.shouldInvoke(window: window, dedupeByWindow: false, refreshID: "same"))
    }
}

@MainActor
final class MainWindowFocusRedrawTests: XCTestCase {
    func testKeyRegainInvalidatesRootContentView() {
        _ = NSApplication.shared

        let appDelegate = AppDelegate()
        let tabManager = TabManager(autoWelcomeIfNeeded: false)
        let windowId = appDelegate.registerMainWindowContextForTesting(tabManager: tabManager)
        defer {
            appDelegate.unregisterMainWindowContextForTesting(windowId: windowId)
        }

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        let splitView = NSSplitView(frame: contentView.bounds)
        splitView.isVertical = true
        splitView.autoresizingMask = [.width, .height]
        splitView.dividerStyle = .thin

        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 420))
        let main = NSView(frame: NSRect(x: 221, y: 0, width: 419, height: 420))
        splitView.addArrangedSubview(sidebar)
        splitView.addArrangedSubview(main)
        contentView.addSubview(splitView)
        splitView.setPosition(220, ofDividerAt: 0)

        let window = CmuxMainWindow(
            contentRect: contentView.bounds,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("cmux.main.\(windowId.uuidString)")
        window.contentView = contentView
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        contentView.layoutSubtreeIfNeeded()
        splitView.adjustSubviews()

        contentView.needsDisplay = false

        appDelegate.handleCmuxWindowResignedKey(
            Notification(name: NSWindow.didResignKeyNotification, object: window)
        )
        appDelegate.handleCmuxWindowBecameKey(
            Notification(name: NSWindow.didBecomeKeyNotification, object: window)
        )

        XCTAssertTrue(
            contentView.needsDisplay,
            "Regaining key focus must invalidate the root content view."
        )
    }
}

@MainActor
final class AppDelegateWindowContextRoutingTests: XCTestCase {
    private func makeMainWindow(id: UUID) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("cmux.main.\(id.uuidString)")
        return window
    }

    func testSynchronizeActiveMainWindowContextPrefersProvidedWindowOverStaleActiveManager() {
        _ = NSApplication.shared
        let app = AppDelegate()

        let windowAId = UUID()
        let windowBId = UUID()
        let windowA = makeMainWindow(id: windowAId)
        let windowB = makeMainWindow(id: windowBId)
        defer {
            windowA.orderOut(nil)
            windowB.orderOut(nil)
        }

        let managerA = TabManager()
        let managerB = TabManager()
        app.registerMainWindow(
            windowA,
            windowId: windowAId,
            tabManager: managerA,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState()
        )
        app.registerMainWindow(
            windowB,
            windowId: windowBId,
            tabManager: managerB,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState()
        )

        windowB.makeKeyAndOrderFront(nil)
        _ = app.synchronizeActiveMainWindowContext(preferredWindow: windowB)
        XCTAssertTrue(app.tabManager === managerB)

        windowA.makeKeyAndOrderFront(nil)
        let resolved = app.synchronizeActiveMainWindowContext(preferredWindow: windowA)
        XCTAssertTrue(resolved === managerA, "Expected provided active window to win over stale active manager")
        XCTAssertTrue(app.tabManager === managerA)
    }

    func testSynchronizeActiveMainWindowContextFallsBackToActiveManagerWithoutFocusedWindow() {
        _ = NSApplication.shared
        let app = AppDelegate()

        let windowAId = UUID()
        let windowBId = UUID()
        let windowA = makeMainWindow(id: windowAId)
        let windowB = makeMainWindow(id: windowBId)
        defer {
            windowA.orderOut(nil)
            windowB.orderOut(nil)
        }

        let managerA = TabManager()
        let managerB = TabManager()
        app.registerMainWindow(
            windowA,
            windowId: windowAId,
            tabManager: managerA,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState()
        )
        app.registerMainWindow(
            windowB,
            windowId: windowBId,
            tabManager: managerB,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState()
        )

        // Seed active manager and clear focus windows to force fallback routing.
        windowA.makeKeyAndOrderFront(nil)
        _ = app.synchronizeActiveMainWindowContext(preferredWindow: windowA)
        XCTAssertTrue(app.tabManager === managerA)
        windowA.orderOut(nil)
        windowB.orderOut(nil)

        let resolved = app.synchronizeActiveMainWindowContext(preferredWindow: nil)
        XCTAssertTrue(resolved === managerA, "Expected fallback to preserve current active manager instead of arbitrary window")
        XCTAssertTrue(app.tabManager === managerA)
    }

    func testSynchronizeActiveMainWindowContextUsesRegisteredWindowEvenIfIdentifierMutates() {
        _ = NSApplication.shared
        let app = AppDelegate()

        let windowId = UUID()
        let window = makeMainWindow(id: windowId)
        defer { window.orderOut(nil) }

        let manager = TabManager()
        app.registerMainWindow(
            window,
            windowId: windowId,
            tabManager: manager,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState()
        )

        // SwiftUI can replace the NSWindow identifier string at runtime.
        window.identifier = NSUserInterfaceItemIdentifier("SwiftUI.AppWindow.IdentifierChanged")

        let resolved = app.synchronizeActiveMainWindowContext(preferredWindow: window)
        XCTAssertTrue(resolved === manager, "Expected registered window object identity to win even if identifier string changed")
        XCTAssertTrue(app.tabManager === manager)
    }

    func testAddWorkspaceWithoutBringToFrontPreservesActiveWindowAndSelection() {
        _ = NSApplication.shared
        let app = AppDelegate()

        let windowAId = UUID()
        let windowBId = UUID()
        let windowA = makeMainWindow(id: windowAId)
        let windowB = makeMainWindow(id: windowBId)
        defer {
            windowA.orderOut(nil)
            windowB.orderOut(nil)
        }

        let managerA = TabManager()
        let managerB = TabManager()
        app.registerMainWindow(
            windowA,
            windowId: windowAId,
            tabManager: managerA,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState()
        )
        app.registerMainWindow(
            windowB,
            windowId: windowBId,
            tabManager: managerB,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState()
        )

        windowA.makeKeyAndOrderFront(nil)
        _ = app.synchronizeActiveMainWindowContext(preferredWindow: windowA)
        XCTAssertTrue(app.tabManager === managerA)

        let originalSelectedA = managerA.selectedTabId
        let originalSelectedB = managerB.selectedTabId
        let originalTabCountB = managerB.tabs.count

        let createdWorkspaceId = app.addWorkspace(windowId: windowBId, bringToFront: false)

        XCTAssertNotNil(createdWorkspaceId)
        XCTAssertTrue(app.tabManager === managerA, "Expected non-focus workspace creation to preserve active window routing")
        XCTAssertEqual(managerA.selectedTabId, originalSelectedA)
        XCTAssertEqual(managerB.selectedTabId, originalSelectedB, "Expected background workspace creation to preserve selected tab")
        XCTAssertEqual(managerB.tabs.count, originalTabCountB + 1)
        XCTAssertTrue(managerB.tabs.contains(where: { $0.id == createdWorkspaceId }))
    }

    func testApplicationOpenURLsAddsWorkspaceForDroppedFolderURL() throws {
        _ = NSApplication.shared
        let app = AppDelegate()

        let windowId = UUID()
        let window = makeMainWindow(id: windowId)
        defer { window.orderOut(nil) }

        let manager = TabManager()
        app.registerMainWindow(
            window,
            windowId: windowId,
            tabManager: manager,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState()
        )

        window.makeKeyAndOrderFront(nil)
        _ = app.synchronizeActiveMainWindowContext(preferredWindow: window)

        let defaults = UserDefaults.standard
        let previousWelcomeShown = defaults.object(forKey: WelcomeSettings.shownKey)
        defaults.set(true, forKey: WelcomeSettings.shownKey)
        defer {
            if let previousWelcomeShown {
                defaults.set(previousWelcomeShown, forKey: WelcomeSettings.shownKey)
            } else {
                defaults.removeObject(forKey: WelcomeSettings.shownKey)
            }
        }

        let rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let droppedDirectory = rootDirectory.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: droppedDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let existingWorkspaceIds = Set(manager.tabs.map(\.id))

        app.application(
            NSApplication.shared,
            open: [URL(fileURLWithPath: droppedDirectory.path)]
        )

        let createdWorkspace = manager.tabs.first { !existingWorkspaceIds.contains($0.id) }
        XCTAssertNotNil(createdWorkspace)
        XCTAssertEqual(createdWorkspace?.currentDirectory, droppedDirectory.path)
    }

    func testApplicationOpenURLsIgnoresBundleSelfPaths() throws {
        _ = NSApplication.shared
        let app = AppDelegate()

        let windowId = UUID()
        let window = makeMainWindow(id: windowId)
        defer { window.orderOut(nil) }

        let manager = TabManager()
        app.registerMainWindow(
            window,
            windowId: windowId,
            tabManager: manager,
            sidebarState: SidebarState(),
            sidebarSelectionState: SidebarSelectionState()
        )

        window.makeKeyAndOrderFront(nil)
        _ = app.synchronizeActiveMainWindowContext(preferredWindow: window)

        let existingWorkspaceIds = Set(manager.tabs.map(\.id))
        let embeddedExecutableURL = try XCTUnwrap(Bundle.main.executableURL?.standardizedFileURL)
        let executableValues = try embeddedExecutableURL.resourceValues(forKeys: [.isExecutableKey])
        XCTAssertEqual(executableValues.isExecutable, true)
        XCTAssertNotNil(
            TerminalDefaultFileOpenRequest(fileURL: embeddedExecutableURL)
        )

        app.application(
            NSApplication.shared,
            open: [embeddedExecutableURL]
        )

        let createdWorkspace = manager.tabs.first { !existingWorkspaceIds.contains($0.id) }
        XCTAssertNil(createdWorkspace)
    }
}


@MainActor
final class AppDelegateLaunchServicesRegistrationTests: XCTestCase {
    func testDefaultTerminalRegistrationKeepsAllAdvertisedTargets() {
        XCTAssertEqual(
            DefaultTerminalRegistration.targetCount,
            DefaultTerminalRegistration.urlSchemes.count + DefaultTerminalRegistration.contentTypeIdentifiers.count
        )
        XCTAssertEqual(
            DefaultTerminalRegistration.contentType(forIdentifier: "com.apple.terminal.shell-script").identifier,
            "com.apple.terminal.shell-script"
        )
    }

    func testScheduleLaunchServicesRegistrationDefersRegisterWork() {
        _ = NSApplication.shared
        let app = AppDelegate()

        var scheduledWork: (@Sendable () -> Void)?
        var registerCallCount = 0

        app.scheduleLaunchServicesBundleRegistrationForTesting(
            bundleURL: URL(fileURLWithPath: "/tmp/../tmp/cmux-launch-services-test.app"),
            scheduler: { work in
                scheduledWork = work
            },
            register: { _ in
                registerCallCount += 1
                return noErr
            }
        )

        XCTAssertEqual(registerCallCount, 0, "Registration should not run inline on the startup call path")
        XCTAssertNotNil(scheduledWork, "Registration work should be handed to the scheduler")

        scheduledWork?()

        XCTAssertEqual(registerCallCount, 1)
    }
}

final class TerminalDefaultFileOpenRequestTests: XCTestCase {
    func testBuildsQuotedLaunchInputForTerminalCommandFile() throws {
        let contentType = DefaultTerminalRegistration.contentType(forIdentifier: "com.apple.terminal.shell-script")
        let url = URL(fileURLWithPath: "/tmp/cmux default's/Run Me.command")

        let request = try XCTUnwrap(TerminalDefaultFileOpenRequest(fileURL: url, contentType: contentType))

        XCTAssertEqual(request.workingDirectory, "/tmp/cmux default's")
        XCTAssertEqual(request.initialInput, "'/tmp/cmux default'\\''s/Run Me.command'\n")
    }

    func testIgnoresPlainTextFiles() {
        let url = URL(fileURLWithPath: "/tmp/notes.txt")

        XCTAssertNil(TerminalDefaultFileOpenRequest(fileURL: url, contentType: .plainText))
    }

    func testBuildsLaunchInputForExtensionlessUnixExecutable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-terminal-default-executable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let executable = directory.appendingPathComponent("runme", isDirectory: false)
        try "#!/bin/sh\necho cmux\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let request = try XCTUnwrap(TerminalDefaultFileOpenRequest(fileURL: executable))

        XCTAssertEqual(request.workingDirectory, directory.path)
        XCTAssertEqual(request.initialInput, "'\(executable.path)'\n")
    }

    func testIgnoresDirectoriesWithTerminalScriptExtension() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-terminal-default-directory-\(UUID().uuidString).command", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertNil(TerminalDefaultFileOpenRequest(fileURL: directory, contentType: .directory))
    }
}


final class FocusFlashPatternTests: XCTestCase {
    func testFocusFlashPatternMatchesTerminalDoublePulseShape() {
        XCTAssertEqual(FocusFlashPattern.values, [0, 1, 0, 1, 0])
        XCTAssertEqual(FocusFlashPattern.keyTimes, [0, 0.25, 0.5, 0.75, 1])
        XCTAssertEqual(FocusFlashPattern.duration, 0.9, accuracy: 0.0001)
        XCTAssertEqual(FocusFlashPattern.curves, [.easeOut, .easeIn, .easeOut, .easeIn])
        XCTAssertEqual(FocusFlashPattern.ringInset, Double(PanelOverlayRingMetrics.inset), accuracy: 0.0001)
        XCTAssertEqual(FocusFlashPattern.ringCornerRadius, Double(PanelOverlayRingMetrics.cornerRadius), accuracy: 0.0001)
    }

    func testFocusFlashPatternSegmentsCoverFullDoublePulseTimeline() {
        let segments = FocusFlashPattern.segments
        XCTAssertEqual(segments.count, 4)

        XCTAssertEqual(segments[0].delay, 0.0, accuracy: 0.0001)
        XCTAssertEqual(segments[0].duration, 0.225, accuracy: 0.0001)
        XCTAssertEqual(segments[0].targetOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(segments[0].curve, .easeOut)

        XCTAssertEqual(segments[1].delay, 0.225, accuracy: 0.0001)
        XCTAssertEqual(segments[1].duration, 0.225, accuracy: 0.0001)
        XCTAssertEqual(segments[1].targetOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(segments[1].curve, .easeIn)

        XCTAssertEqual(segments[2].delay, 0.45, accuracy: 0.0001)
        XCTAssertEqual(segments[2].duration, 0.225, accuracy: 0.0001)
        XCTAssertEqual(segments[2].targetOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(segments[2].curve, .easeOut)

        XCTAssertEqual(segments[3].delay, 0.675, accuracy: 0.0001)
        XCTAssertEqual(segments[3].duration, 0.225, accuracy: 0.0001)
        XCTAssertEqual(segments[3].targetOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(segments[3].curve, .easeIn)
    }
}


@available(macOS 26.0, *)
private struct DragConfigurationOperationsSnapshot: Equatable {
    let allowCopy: Bool
    let allowMove: Bool
    let allowDelete: Bool
    let allowAlias: Bool
}

@available(macOS 26.0, *)
private enum DragConfigurationSnapshotError: Error {
    case missingBoolField(primary: String, fallback: String?)
}

@available(macOS 26.0, *)
private func dragConfigurationOperationsSnapshot<T>(from operations: T) throws -> DragConfigurationOperationsSnapshot {
    let mirror = Mirror(reflecting: operations)

    func readBool(_ primary: String, fallback: String? = nil) throws -> Bool {
        if let value = mirror.descendant(primary) as? Bool {
            return value
        }
        if let fallback, let value = mirror.descendant(fallback) as? Bool {
            return value
        }
        throw DragConfigurationSnapshotError.missingBoolField(primary: primary, fallback: fallback)
    }

    return try DragConfigurationOperationsSnapshot(
        allowCopy: readBool("allowCopy", fallback: "_allowCopy"),
        allowMove: readBool("allowMove", fallback: "_allowMove"),
        allowDelete: readBool("allowDelete", fallback: "_allowDelete"),
        allowAlias: readBool("allowAlias", fallback: "_allowAlias")
    )
}

#if compiler(>=6.2)
@MainActor
final class InternalTabDragConfigurationTests: XCTestCase {
    func testDisablesExternalOperationsForInternalTabDrags() throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Requires macOS 26 drag configuration APIs")
        }

        let configuration = InternalTabDragConfigurationProvider.value
        let withinApp = try dragConfigurationOperationsSnapshot(from: configuration.operationsWithinApp)
        let outsideApp = try dragConfigurationOperationsSnapshot(from: configuration.operationsOutsideApp)

        XCTAssertEqual(
            withinApp,
            DragConfigurationOperationsSnapshot(
                allowCopy: false,
                allowMove: true,
                allowDelete: false,
                allowAlias: false
            )
        )

        XCTAssertEqual(
            outsideApp,
            DragConfigurationOperationsSnapshot(
                allowCopy: false,
                allowMove: false,
                allowDelete: false,
                allowAlias: false
            )
        )
    }
}


@MainActor
final class InternalTabDragBundleDeclarationTests: XCTestCase {
    private func exportedTypeIdentifiers(bundle: Bundle) -> Set<String> {
        let declarations = (bundle.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]]) ?? []
        return Set(declarations.compactMap { $0["UTTypeIdentifier"] as? String })
    }

    func testAppBundleExportsInternalDragTypes() {
        let exported = exportedTypeIdentifiers(bundle: Bundle(for: AppDelegate.self))

        XCTAssertTrue(
            exported.contains("com.splittabbar.tabtransfer"),
            "Expected app bundle to export bonsplit tab-transfer type, got \(exported)"
        )
        XCTAssertTrue(
            exported.contains("com.cmux.sidebar-tab-reorder"),
            "Expected app bundle to export sidebar tab-reorder type, got \(exported)"
        )
    }
}
#endif


@MainActor
final class WindowDragHandleHitTests: XCTestCase {
    private final class CapturingView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }
    }

    private final class HostContainerView: NSView {}
    private final class BlockingTopHitContainerView: NSView {
        var hitCount = 0

        override func hitTest(_ point: NSPoint) -> NSView? {
            hitCount += 1
            return bounds.contains(point) ? self : nil
        }
    }
    private final class PassThroughProbeView: NSView {
        var onHitTest: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else { return nil }
            onHitTest?()
            return nil
        }
    }
    private final class PassiveHostContainerView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else { return nil }
            return super.hitTest(point) ?? self
        }
    }

    private final class SidebarActionRegionView: NSView, MinimalModeSidebarControlActionHitRegionProviding {
        nonisolated(unsafe) var config = TitlebarControlsStyle.classic.config

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        nonisolated func containsMinimalModeTitlebarControlHit(localPoint: NSPoint) -> Bool {
            minimalModeSidebarControlActionSlot(localPoint: localPoint) != nil
        }

        nonisolated func minimalModeSidebarControlActionSlot(localPoint: NSPoint) -> MinimalModeSidebarControlActionSlot? {
            let ranges = TitlebarControlsHitRegions.buttonXRanges(config: config)
            for (index, range) in ranges.enumerated() where range.contains(localPoint.x) {
                return MinimalModeSidebarControlActionSlot(rawValue: index)
            }
            return nil
        }
    }

    private final class MutatingSiblingView: NSView {
        weak var container: NSView?
        private var didMutate = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else { return nil }
            guard !didMutate, let container else { return nil }
            didMutate = true
            let transient = NSView(frame: .zero)
            container.addSubview(transient)
            transient.removeFromSuperview()
            return nil
        }
    }

    private final class ReentrantDragHandleView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            let shouldCapture = windowDragHandleShouldCaptureHit(point, in: self, eventType: .leftMouseDown, eventWindow: self.window)
            return shouldCapture ? self : nil
        }
    }

    private final class RecordingTitlebarActionWindow: NSWindow {
        var zoomCallCount = 0
        var miniaturizeCallCount = 0

        override func zoom(_ sender: Any?) {
            zoomCallCount += 1
        }

        override func miniaturize(_ sender: Any?) {
            miniaturizeCallCount += 1
        }
    }

    /// A sibling view whose hitTest re-enters windowDragHandleShouldCaptureHit,
    /// simulating the crash path where sibling.hitTest triggers a SwiftUI layout
    /// pass that calls back into the drag handle's hit resolution.
    private final class ReentrantSiblingView: NSView {
        weak var dragHandle: NSView?
        var reenteredResult: Bool?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point), let dragHandle else { return nil }
            // Simulate the re-entry: during sibling hit test, SwiftUI layout
            // calls windowDragHandleShouldCaptureHit on the drag handle again.
            reenteredResult = windowDragHandleShouldCaptureHit(
                point, in: dragHandle, eventType: .leftMouseDown, eventWindow: dragHandle.window
            )
            return nil
        }
    }

    private static func firstSubview(
        in view: NSView,
        matching predicate: (NSView) -> Bool
    ) -> NSView? {
        if predicate(view) {
            return view
        }

        for subview in view.subviews {
            if let match = firstSubview(in: subview, matching: predicate) {
                return match
            }
        }

        return nil
    }

    private static func firstCapturableTitlebarPoint(
        in dragHandle: NSView,
        window: NSWindow
    ) -> NSPoint? {
        let bounds = dragHandle.bounds.insetBy(dx: 4, dy: 4)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let yCandidates = [
            bounds.midY,
            bounds.minY + bounds.height * 0.25,
            bounds.minY + bounds.height * 0.75
        ]

        for y in yCandidates {
            var x = bounds.maxX
            while x >= bounds.minX {
                let point = NSPoint(x: x, y: y)
                if windowDragHandleShouldCaptureHit(
                    point,
                    in: dragHandle,
                    eventType: .leftMouseDown,
                    eventWindow: window
                ) {
                    return point
                }
                x -= 4
            }
        }

        return nil
    }

    func testDragHandleCapturesHitWhenNoSiblingClaimsPoint() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 36))
        let dragHandle = NSView(frame: container.bounds)
        container.addSubview(dragHandle)

        XCTAssertTrue(
            windowDragHandleShouldCaptureHit(NSPoint(x: 180, y: 18), in: dragHandle, eventType: .leftMouseDown),
            "Empty titlebar space should drag the window"
        )
    }

    func testDragHandleYieldsWhenSiblingClaimsPoint() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 36))
        let dragHandle = NSView(frame: container.bounds)
        container.addSubview(dragHandle)

        let folderIconHost = CapturingView(frame: NSRect(x: 10, y: 10, width: 16, height: 16))
        container.addSubview(folderIconHost)

        XCTAssertFalse(
            windowDragHandleShouldCaptureHit(NSPoint(x: 14, y: 14), in: dragHandle, eventType: .leftMouseDown),
            "Interactive titlebar controls should receive the mouse event"
        )
        XCTAssertTrue(windowDragHandleShouldCaptureHit(NSPoint(x: 180, y: 18), in: dragHandle, eventType: .leftMouseDown))
    }

    func testTitlebarControlGapsAreOutsideButtonHitColumns() {
        let config = TitlebarControlsStyle.classic.config
        let ranges = TitlebarControlsHitRegions.buttonXRanges(config: config)
        XCTAssertEqual(ranges.count, MinimalModeSidebarControlActionSlot.allCases.count)
        XCTAssertEqual(
            ranges[0].lowerBound,
            TitlebarControlsLayoutMetrics.hintLeadingPadding + config.groupPadding.leading,
            accuracy: 0.001,
            "Hidden titlebar hit regions should share the visible titlebar control leading position."
        )

        XCTAssertTrue(
            TitlebarControlsHitRegions.pointFallsInButtonColumn(
                NSPoint(x: ranges[0].lowerBound + 1, y: 14),
                config: config
            ),
            "Icon button columns should stay interactive"
        )

        let firstGapX = (ranges[0].upperBound + ranges[1].lowerBound) / 2
        let secondGapX = (ranges[1].upperBound + ranges[2].lowerBound) / 2

        XCTAssertFalse(
            TitlebarControlsHitRegions.pointFallsInButtonColumn(NSPoint(x: firstGapX, y: 14), config: config),
            "The gap between the sidebar and notification icons should remain available for window dragging"
        )
        XCTAssertFalse(
            TitlebarControlsHitRegions.pointFallsInButtonColumn(NSPoint(x: secondGapX, y: 14), config: config),
            "The gap between the notification and new-workspace icons should remain available for window dragging"
        )
    }

    func testDragHandleYieldsToRegisteredMinimalModeSidebarButtonColumns() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let dragHandle = NSView(frame: contentView.bounds)
        dragHandle.autoresizingMask = [.width, .height]
        contentView.addSubview(dragHandle)

        let controlRegion = SidebarActionRegionView(
            frame: NSRect(
                x: 72,
                y: 88,
                width: MinimalModeSidebarTitlebarControlsMetrics.hostWidth,
                height: MinimalModeSidebarTitlebarControlsMetrics.hostHeight
            )
        )
        contentView.addSubview(controlRegion)
        MinimalModeTitlebarControlHitRegionRegistry.register(controlRegion)
        defer { MinimalModeTitlebarControlHitRegionRegistry.unregister(controlRegion) }

        let ranges = TitlebarControlsHitRegions.buttonXRanges(config: controlRegion.config)
        let backButtonPoint = NSPoint(
            x: controlRegion.frame.minX + ranges[MinimalModeSidebarControlActionSlot.focusHistoryBack.rawValue].lowerBound + 1,
            y: controlRegion.frame.midY
        )
        XCTAssertTrue(isMinimalModeTitlebarControlHit(window: window, locationInWindow: backButtonPoint))
        XCTAssertFalse(
            windowDragHandleShouldCaptureHit(
                dragHandle.convert(backButtonPoint, from: nil),
                in: dragHandle,
                eventType: .leftMouseDown,
                eventWindow: window
            ),
            "Registered minimal-mode titlebar buttons should not fall through to the window drag handle."
        )

        let emptyTitlebarPoint = NSPoint(x: contentView.bounds.maxX - 20, y: controlRegion.frame.midY)
        XCTAssertTrue(
            windowDragHandleShouldCaptureHit(
                dragHandle.convert(emptyTitlebarPoint, from: nil),
                in: dragHandle,
                eventType: .leftMouseDown,
                eventWindow: window
            ),
            "Empty titlebar space should still be draggable."
        )
    }

    func testMinimalModeSidebarFallbackHitUsesHardcodedLeadingInset() {
        let suiteName = "WindowDragHandleHitTests.leadingInset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(WorkspacePresentationModeSettings.Mode.minimal.rawValue, forKey: WorkspacePresentationModeSettings.modeKey)
        defaults.set(TitlebarControlsStyle.classic.rawValue, forKey: "titlebarControlsStyle")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("cmux.main.test")
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let firstButtonX = TitlebarControlsHitRegions.buttonXRanges(config: TitlebarControlsStyle.classic.config)[0].lowerBound + 1
        let titlebarY = contentView.bounds.maxY - 4
        XCTAssertEqual(
            minimalModeSidebarControlActionSlot(
                window: window,
                locationInWindow: NSPoint(
                    x: CGFloat(MinimalModeTitlebarDebugSettings.defaultLeftControlsLeadingInset) + firstButtonX,
                    y: titlebarY
                ),
                defaults: defaults
            ),
            .toggleSidebar
        )
    }

    func testMinimalModeSidebarTitlebarControlsAlignWithTrafficLightCenter() {
        let defaults = UserDefaults.standard
        let savedMode = defaults.object(forKey: WorkspacePresentationModeSettings.modeKey)
        // WindowDecorationsController.apply reads the production presentation-mode setting
        // from UserDefaults.standard, so this test saves and restores the shared key narrowly.
        defaults.set(WorkspacePresentationModeSettings.Mode.minimal.rawValue, forKey: WorkspacePresentationModeSettings.modeKey)
        defer {
            if let savedMode {
                defaults.set(savedMode, forKey: WorkspacePresentationModeSettings.modeKey)
            } else {
                defaults.removeObject(forKey: WorkspacePresentationModeSettings.modeKey)
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("cmux.main.test")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        defer { window.orderOut(nil) }

        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }
        guard let closeButton = window.standardWindowButton(.closeButton),
              let closeButtonSuperview = closeButton.superview else {
            XCTFail("Expected close traffic-light button")
            return
        }

        let controller = WindowDecorationsController()
        controller.apply(to: window)

        guard let target = contentView.subviews.compactMap({ $0 as? MinimalModeSidebarControlActionView }).first else {
            XCTFail("Expected minimal sidebar titlebar click target")
            return
        }

        let trafficLightFrame = closeButtonSuperview.convert(closeButton.frame, to: contentView)
        XCTAssertEqual(
            target.frame.midY,
            trafficLightFrame.midY,
            accuracy: 0.25,
            "Minimal-mode sidebar controls should share the traffic-light center Y"
        )
    }

    func testTitlebarChromeSettingsUseDefaultsAndStoredOverrides() {
        let suiteName = "WindowDragHandleHitTests.titlebarChromeSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let snapshot = MinimalModeTitlebarDebugSettings.snapshot(defaults: defaults)
        XCTAssertEqual(
            snapshot.leftControlsLeadingInset,
            MinimalModeTitlebarDebugSettings.defaultLeftControlsLeadingInset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.leftControlsTopInset,
            MinimalModeTitlebarDebugSettings.defaultLeftControlsTopInset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MinimalModeTitlebarDebugSettings.leftControlsLeadingInset(defaults: defaults),
            CGFloat(MinimalModeTitlebarDebugSettings.defaultLeftControlsLeadingInset),
            accuracy: 0.001
        )
        XCTAssertEqual(
            MinimalModeSidebarTitlebarControlsMetrics.topInset(defaults: defaults),
            CGFloat(MinimalModeTitlebarDebugSettings.defaultLeftControlsTopInset),
            accuracy: 0.001
        )

        defaults.set(44.5, forKey: MinimalModeTitlebarDebugSettings.leftControlsLeadingInsetKey)
        defaults.set(6.5, forKey: MinimalModeTitlebarDebugSettings.leftControlsTopInsetKey)
        defaults.set(12.0, forKey: "titlebarDebug.trafficLightsXOffset")
        defaults.set(-3.0, forKey: "titlebarDebug.trafficLightsYOffset")
        defaults.set(88.0, forKey: MinimalModeTitlebarDebugSettings.trafficLightTabBarInsetKey)
        defaults.set(92.0, forKey: MinimalModeTitlebarDebugSettings.trafficLightTitlebarLeadingInsetKey)

        let storedSnapshot = MinimalModeTitlebarDebugSettings.snapshot(defaults: defaults)
        XCTAssertEqual(storedSnapshot.leftControlsLeadingInset, 44.5, accuracy: 0.001)
        XCTAssertEqual(storedSnapshot.leftControlsTopInset, 6.5, accuracy: 0.001)
        XCTAssertEqual(storedSnapshot.trafficLightTabBarLeadingInset, 88.0, accuracy: 0.001)
        XCTAssertEqual(storedSnapshot.trafficLightTitlebarLeadingInset, 92.0, accuracy: 0.001)

        defaults.set(999.0, forKey: MinimalModeTitlebarDebugSettings.leftControlsLeadingInsetKey)
        XCTAssertEqual(
            MinimalModeTitlebarDebugSettings.leftControlsLeadingInset(defaults: defaults),
            CGFloat(MinimalModeTitlebarDebugSettings.horizontalInsetRange.upperBound),
            accuracy: 0.001
        )
    }

    func testTitlebarChromeSettingsIgnoreLegacyNativeTrafficLightOffsets() {
        let suiteName = "WindowDragHandleHitTests.titlebarChromeLegacyTrafficLights.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(44.0, forKey: "titlebarDebug.trafficLightsXOffset")
        defaults.set(-12.0, forKey: "titlebarDebug.trafficLightsYOffset")

        let snapshot = MinimalModeTitlebarDebugSettings.snapshot(defaults: defaults)
        XCTAssertEqual(
            snapshot,
            MinimalModeTitlebarDebugSnapshot(
                leftControlsLeadingInset: MinimalModeTitlebarDebugSettings.defaultLeftControlsLeadingInset,
                leftControlsTopInset: MinimalModeTitlebarDebugSettings.defaultLeftControlsTopInset,
                trafficLightTabBarLeadingInset: MinimalModeTitlebarDebugSettings.defaultTrafficLightTabBarInset,
                trafficLightTitlebarLeadingInset: MinimalModeTitlebarDebugSettings.defaultTrafficLightTitlebarLeadingInset
            )
        )
    }

    func testDragHandleIgnoresHiddenSiblingWhenResolvingHit() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 36))
        let dragHandle = NSView(frame: container.bounds)
        container.addSubview(dragHandle)

        let hidden = CapturingView(frame: NSRect(x: 10, y: 10, width: 16, height: 16))
        hidden.isHidden = true
        container.addSubview(hidden)

        XCTAssertTrue(windowDragHandleShouldCaptureHit(NSPoint(x: 14, y: 14), in: dragHandle, eventType: .leftMouseDown))
    }

    func testDragHandleDoesNotCaptureOutsideBounds() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 36))
        let dragHandle = NSView(frame: container.bounds)
        container.addSubview(dragHandle)

        XCTAssertFalse(windowDragHandleShouldCaptureHit(NSPoint(x: 240, y: 18), in: dragHandle, eventType: .leftMouseDown))
    }

    func testDragHandleSkipsCaptureForPassivePointerEvents() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 36))
        let dragHandle = NSView(frame: container.bounds)
        container.addSubview(dragHandle)

        let point = NSPoint(x: 180, y: 18)
        XCTAssertFalse(windowDragHandleShouldCaptureHit(point, in: dragHandle, eventType: .mouseMoved))
        XCTAssertFalse(windowDragHandleShouldCaptureHit(point, in: dragHandle, eventType: .cursorUpdate))
        XCTAssertFalse(windowDragHandleShouldCaptureHit(point, in: dragHandle, eventType: nil))
        XCTAssertTrue(windowDragHandleShouldCaptureHit(point, in: dragHandle, eventType: .leftMouseDown))
    }

    func testDragHandleNeverCapturesRegisteredBonsplitPaneTab() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let container = NSView(frame: contentView.bounds)
        contentView.addSubview(container)

        let dragHandle = NSView(frame: container.bounds)
        container.addSubview(dragHandle)

        let tabRegion = FakeBonsplitTabItemRegionView(frame: NSRect(x: 20, y: 82, width: 220, height: 30))
        tabRegion.tabFrames = [CGRect(x: 8, y: 0, width: 96, height: 30)]
        container.addSubview(tabRegion)
        BonsplitTabItemHitRegionRegistry.register(tabRegion)
        defer { BonsplitTabItemHitRegionRegistry.unregister(tabRegion) }

        let tabWindowPoint = tabRegion.convert(NSPoint(x: 48, y: 15), to: nil)
        let tabDragHandlePoint = dragHandle.convert(tabWindowPoint, from: nil)
        XCTAssertFalse(
            windowDragHandleShouldCaptureHit(
                tabDragHandlePoint,
                in: dragHandle,
                eventType: .leftMouseDown,
                eventWindow: window
            ),
            "A visible pane tab must own its mouse-down; the titlebar drag handle must not turn it into a window drag"
        )

        let emptyWindowPoint = tabRegion.convert(NSPoint(x: 180, y: 15), to: nil)
        let emptyDragHandlePoint = dragHandle.convert(emptyWindowPoint, from: nil)
        XCTAssertTrue(
            windowDragHandleShouldCaptureHit(
                emptyDragHandlePoint,
                in: dragHandle,
                eventType: .leftMouseDown,
                eventWindow: window
            ),
            "Empty tab-strip chrome should remain available for app-window dragging"
        )
    }

    func testTabBarEmptyChromeOverlayNeverCapturesRegisteredBonsplitPaneTabWhenFrameCacheIsEmpty() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let dragZone = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 72, width: 320, height: 30))
        dragZone.hitRegion = .trailingEmptyChrome(tabFrames: [], reservedTrailingWidth: 48)
        dragZone.hitTestEventTypeOverride = .leftMouseDown
        contentView.addSubview(dragZone)

        let tabRegion = FakeBonsplitTabItemRegionView(frame: NSRect(x: 10, y: 72, width: 90, height: 30))
        tabRegion.tabFrames = [tabRegion.bounds]
        contentView.addSubview(tabRegion)
        BonsplitTabItemHitRegionRegistry.register(tabRegion)
        defer { BonsplitTabItemHitRegionRegistry.unregister(tabRegion) }

        XCTAssertNil(
            dragZone.hitTest(NSPoint(x: 40, y: 15)),
            "The empty-chrome overlay must not turn a pane-tab mouse-down into an app-window drag while tab frames are still populating"
        )
        XCTAssertIdentical(
            dragZone.hitTest(NSPoint(x: 140, y: 15)),
            dragZone,
            "Empty tab-strip chrome after the registered tab should still be available for app-window dragging"
        )
    }

    func testDragHandleSkipsForeignLeftMouseDownDuringLaunch() {
        let point = NSPoint(x: 180, y: 18)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 36),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let container = NSView(frame: contentView.bounds)
        container.autoresizingMask = [.width, .height]
        contentView.addSubview(container)

        let dragHandle = NSView(frame: container.bounds)
        dragHandle.autoresizingMask = [.width, .height]
        container.addSubview(dragHandle)

        let foreignWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 36),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { foreignWindow.orderOut(nil) }

        XCTAssertFalse(
            windowDragHandleShouldCaptureHit(
                point,
                in: dragHandle,
                eventType: .leftMouseDown,
                eventWindow: nil
            ),
            "Launch activation events without a matching window should not trigger drag-handle hierarchy walk"
        )

        XCTAssertFalse(
            windowDragHandleShouldCaptureHit(
                point,
                in: dragHandle,
                eventType: .leftMouseDown,
                eventWindow: foreignWindow
            ),
            "Left mouse-down events for a different window should be treated as passive"
        )

        XCTAssertTrue(
            windowDragHandleShouldCaptureHit(
                point,
                in: dragHandle,
                eventType: .leftMouseDown,
                eventWindow: window
            ),
            "Left mouse-down events for this window should still capture empty titlebar space"
        )
    }

    func testPassiveHostingTopHitClassification() {
        XCTAssertTrue(windowDragHandleShouldTreatTopHitAsPassiveHost(HostContainerView(frame: .zero)))
        XCTAssertFalse(windowDragHandleShouldTreatTopHitAsPassiveHost(NSButton(frame: .zero)))
    }

    func testMinimalModeTitlebarControlRegionRegistryMatchesVisibleRegisteredView() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let controlRegion = NSView(frame: NSRect(x: 72, y: 88, width: 124, height: 28))
        contentView.addSubview(controlRegion)
        MinimalModeTitlebarControlHitRegionRegistry.register(controlRegion)
        defer { MinimalModeTitlebarControlHitRegionRegistry.unregister(controlRegion) }

        XCTAssertTrue(isMinimalModeTitlebarControlHit(window: window, locationInWindow: NSPoint(x: 100, y: 100)))
        XCTAssertFalse(isMinimalModeTitlebarControlHit(window: window, locationInWindow: NSPoint(x: 20, y: 100)))

        controlRegion.isHidden = true
        XCTAssertFalse(isMinimalModeTitlebarControlHit(window: window, locationInWindow: NSPoint(x: 100, y: 100)))
    }

    func testMinimalModeTitlebarControlRegionCanLimitHitsInsideRegisteredView() {
        final class ButtonOnlyRegion: NSView, MinimalModeTitlebarControlHitRegionProviding {
            nonisolated func containsMinimalModeTitlebarControlHit(localPoint: NSPoint) -> Bool {
                localPoint.x >= 24 && localPoint.x <= 48
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let controlRegion = ButtonOnlyRegion(frame: NSRect(x: 72, y: 88, width: 124, height: 28))
        contentView.addSubview(controlRegion)
        MinimalModeTitlebarControlHitRegionRegistry.register(controlRegion)
        defer { MinimalModeTitlebarControlHitRegionRegistry.unregister(controlRegion) }

        XCTAssertTrue(
            isMinimalModeTitlebarControlHit(window: window, locationInWindow: NSPoint(x: 100, y: 100)),
            "Expected points inside the provider's button range to suppress titlebar double-click handling."
        )
        XCTAssertFalse(
            isMinimalModeTitlebarControlHit(window: window, locationInWindow: NSPoint(x: 136, y: 100)),
            "Expected gaps inside the registered view to keep behaving like titlebar chrome."
        )
    }

    func testMinimalModeSidebarActionSlotUsesRegisteredHostFrame() {
        let suiteName = "WindowDragHandleHitTests.sidebarHostFrame.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(WorkspacePresentationModeSettings.Mode.minimal.rawValue, forKey: WorkspacePresentationModeSettings.modeKey)
        defaults.set(TitlebarControlsStyle.classic.rawValue, forKey: "titlebarControlsStyle")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("cmux.main.test")
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let controlRegion = SidebarActionRegionView(frame: NSRect(x: 88, y: 88, width: 124, height: 28))
        contentView.addSubview(controlRegion)
        MinimalModeTitlebarControlHitRegionRegistry.register(controlRegion)
        defer { MinimalModeTitlebarControlHitRegionRegistry.unregister(controlRegion) }

        XCTAssertEqual(
            minimalModeSidebarControlActionSlot(
                window: window,
                locationInWindow: NSPoint(x: controlRegion.frame.minX + 50, y: controlRegion.frame.minY + 14),
                defaults: defaults
            ),
            .showNotifications,
            "Sidebar control actions should use the actual registered host frame instead of a fixed window x origin."
        )
    }

    func testMinimalModeSidebarActionSlotUsesRegisteredHostFrameBelowFallbackBand() {
        let suiteName = "WindowDragHandleHitTests.sidebarHostFrameBand.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(WorkspacePresentationModeSettings.Mode.minimal.rawValue, forKey: WorkspacePresentationModeSettings.modeKey)
        defaults.set(TitlebarControlsStyle.classic.rawValue, forKey: "titlebarControlsStyle")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("cmux.main.test")
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let controlRegion = SidebarActionRegionView(frame: NSRect(x: 88, y: 88, width: 124, height: 28))
        contentView.addSubview(controlRegion)
        MinimalModeTitlebarControlHitRegionRegistry.register(controlRegion)
        defer { MinimalModeTitlebarControlHitRegionRegistry.unregister(controlRegion) }

        let point = NSPoint(x: controlRegion.frame.minX + 14, y: controlRegion.frame.minY + 1)
        XCTAssertFalse(
            isPointInMinimalModeTitlebarBand(
                isEnabled: true,
                point: point,
                bounds: contentView.bounds,
                topStripHeight: MinimalModeChromeMetrics.titlebarHeight
            ),
            "The regression point should sit inside the visual control host but outside the hard-coded fallback band."
        )
        XCTAssertEqual(
            minimalModeSidebarControlActionSlot(window: window, locationInWindow: point, defaults: defaults),
            .toggleSidebar
        )
        XCTAssertTrue(
            isMinimalModeSidebarChromeHoverCandidate(window: window, locationInWindow: point, defaults: defaults),
            "Hover reveal should follow the real control host frame."
        )
    }

    func testSuppressedTitlebarDoubleClickConsumesWithoutWindowAction() {
        XCTAssertEqual(
            handleTitlebarDoubleClick(window: nil, behavior: .suppress),
            .suppressed
        )
        XCTAssertEqual(
            handleTitlebarDoubleClick(window: nil, behavior: .standardAction),
            .ignored
        )
        XCTAssertTrue(TitlebarDoubleClickHandlingResult.suppressed.consumesEvent)
        XCTAssertFalse(TitlebarDoubleClickHandlingResult.ignored.consumesEvent)
    }

    func testMinimalModeDoubleClickHandlerOnlyHandlesTopStripDoubleClicks() {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 300)

        XCTAssertTrue(
            shouldHandleMinimalModeTitlebarDoubleClick(
                isEnabled: true,
                clickCount: 2,
                point: NSPoint(x: 200, y: 292),
                bounds: bounds,
                topStripHeight: 30
            )
        )
        XCTAssertFalse(
            shouldHandleMinimalModeTitlebarDoubleClick(
                isEnabled: true,
                clickCount: 2,
                point: NSPoint(x: 200, y: 240),
                bounds: bounds,
                topStripHeight: 30
            )
        )
        XCTAssertFalse(
            shouldHandleMinimalModeTitlebarDoubleClick(
                isEnabled: false,
                clickCount: 2,
                point: NSPoint(x: 200, y: 292),
                bounds: bounds,
                topStripHeight: 30
            )
        )
        XCTAssertFalse(
            shouldHandleMinimalModeTitlebarDoubleClick(
                isEnabled: true,
                clickCount: 1,
                point: NSPoint(x: 200, y: 292),
                bounds: bounds,
                topStripHeight: 30
            )
        )
    }

    func testMinimalModeWindowDoubleClickRequiresMainTopStrip() {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 300)

        XCTAssertTrue(
            shouldHandleMinimalModeWindowTitlebarDoubleClick(
                isMinimalMode: true,
                isFullScreen: false,
                isMainWindow: true,
                clickCount: 2,
                locationInWindow: NSPoint(x: 200, y: 292),
                contentBounds: bounds,
                titlebarBandHeight: 30
            )
        )
        XCTAssertFalse(
            shouldHandleMinimalModeWindowTitlebarDoubleClick(
                isMinimalMode: false,
                isFullScreen: false,
                isMainWindow: true,
                clickCount: 2,
                locationInWindow: NSPoint(x: 200, y: 292),
                contentBounds: bounds,
                titlebarBandHeight: 30
            )
        )
        XCTAssertFalse(
            shouldHandleMinimalModeWindowTitlebarDoubleClick(
                isMinimalMode: true,
                isFullScreen: true,
                isMainWindow: true,
                clickCount: 2,
                locationInWindow: NSPoint(x: 200, y: 292),
                contentBounds: bounds,
                titlebarBandHeight: 30
            )
        )
        XCTAssertFalse(
            shouldHandleMinimalModeWindowTitlebarDoubleClick(
                isMinimalMode: true,
                isFullScreen: false,
                isMainWindow: false,
                clickCount: 2,
                locationInWindow: NSPoint(x: 200, y: 292),
                contentBounds: bounds,
                titlebarBandHeight: 30
            )
        )
        XCTAssertFalse(
            shouldHandleMinimalModeWindowTitlebarDoubleClick(
                isMinimalMode: true,
                isFullScreen: false,
                isMainWindow: true,
                clickCount: 2,
                locationInWindow: NSPoint(x: 200, y: 240),
                contentBounds: bounds,
                titlebarBandHeight: 30
            )
        )
    }

    func testMinimalModeTitlebarConsecutiveClicksCanFormDoubleClick() {
        let previous = MinimalModeTitlebarClickRecord(
            windowNumber: 42,
            timestamp: 10,
            locationInWindow: NSPoint(x: 200, y: 292)
        )

        XCTAssertTrue(
            minimalModeTitlebarClickFormsDoubleClick(
                clickCount: 1,
                timestamp: 10.2,
                locationInWindow: NSPoint(x: 201, y: 291),
                windowNumber: 42,
                previous: previous,
                doubleClickInterval: 0.5
            )
        )
        XCTAssertFalse(
            minimalModeTitlebarClickFormsDoubleClick(
                clickCount: 1,
                timestamp: 10.65,
                locationInWindow: NSPoint(x: 201, y: 291),
                windowNumber: 42,
                previous: previous,
                doubleClickInterval: 0.5
            )
        )
        XCTAssertTrue(
            minimalModeTitlebarClickFormsDoubleClick(
                clickCount: 1,
                timestamp: 10.62,
                locationInWindow: NSPoint(x: 201, y: 291),
                windowNumber: 42,
                previous: previous,
                doubleClickInterval: 0.5,
                doubleClickIntervalTolerance: 0.15
            )
        )
        XCTAssertTrue(
            minimalModeTitlebarClickFormsDoubleClick(
                clickCount: 2,
                timestamp: 20,
                locationInWindow: NSPoint(x: 20, y: 20),
                windowNumber: 99,
                previous: nil,
                doubleClickInterval: 0.5
            )
        )
        XCTAssertFalse(
            minimalModeTitlebarClickFormsDoubleClick(
                clickCount: 1,
                timestamp: 10.8,
                locationInWindow: NSPoint(x: 201, y: 291),
                windowNumber: 42,
                previous: previous,
                doubleClickInterval: 0.5
            )
        )
        XCTAssertFalse(
            minimalModeTitlebarClickFormsDoubleClick(
                clickCount: 1,
                timestamp: 10.2,
                locationInWindow: NSPoint(x: 240, y: 292),
                windowNumber: 42,
                previous: previous,
                doubleClickInterval: 0.5
            )
        )
        XCTAssertFalse(
            minimalModeTitlebarClickFormsDoubleClick(
                clickCount: 1,
                timestamp: 10.2,
                locationInWindow: NSPoint(x: 201, y: 291),
                windowNumber: 43,
                previous: previous,
                doubleClickInterval: 0.5
            )
        )
    }

    func testDragHandleIgnoresPassiveHostSiblingHit() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 36))
        let dragHandle = NSView(frame: container.bounds)
        container.addSubview(dragHandle)

        let passiveHost = PassiveHostContainerView(frame: container.bounds)
        container.addSubview(passiveHost)

        XCTAssertTrue(
            windowDragHandleShouldCaptureHit(NSPoint(x: 180, y: 18), in: dragHandle, eventType: .leftMouseDown),
            "Passive host wrappers should not block titlebar drag capture"
        )
    }

    func testDragHandleRespectsInteractiveChildInsidePassiveHost() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 36))
        let dragHandle = NSView(frame: container.bounds)
        container.addSubview(dragHandle)

        let passiveHost = PassiveHostContainerView(frame: container.bounds)
        let folderControl = CapturingView(frame: NSRect(x: 10, y: 10, width: 16, height: 16))
        passiveHost.addSubview(folderControl)
        container.addSubview(passiveHost)

        XCTAssertFalse(
            windowDragHandleShouldCaptureHit(NSPoint(x: 14, y: 14), in: dragHandle, eventType: .leftMouseDown),
            "Interactive controls inside passive host wrappers should still receive hits"
        )
    }

    func testTopHitResolutionStateIsScopedPerWindow() {
        let point = NSPoint(x: 100, y: 18)

        let outerWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 36),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { outerWindow.orderOut(nil) }
        guard let outerContentView = outerWindow.contentView else {
            XCTFail("Expected outer content view")
            return
        }
        let outerContainer = NSView(frame: outerContentView.bounds)
        outerContainer.autoresizingMask = [.width, .height]
        outerContentView.addSubview(outerContainer)
        let outerDragHandle = NSView(frame: outerContainer.bounds)
        outerDragHandle.autoresizingMask = [.width, .height]
        outerContainer.addSubview(outerDragHandle)

        let nestedWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 36),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { nestedWindow.orderOut(nil) }
        guard let nestedContentView = nestedWindow.contentView else {
            XCTFail("Expected nested content view")
            return
        }
        let nestedContainer = NSView(frame: nestedContentView.bounds)
        nestedContainer.autoresizingMask = [.width, .height]
        nestedContentView.addSubview(nestedContainer)
        let nestedDragHandle = NSView(frame: nestedContainer.bounds)
        nestedDragHandle.autoresizingMask = [.width, .height]
        nestedContainer.addSubview(nestedDragHandle)
        let nestedBlockingOverlay = BlockingTopHitContainerView(frame: nestedContainer.bounds)
        nestedBlockingOverlay.autoresizingMask = [.width, .height]
        nestedContainer.addSubview(nestedBlockingOverlay)

        XCTAssertFalse(
            windowDragHandleShouldCaptureHit(point, in: nestedDragHandle, eventType: .leftMouseDown, eventWindow: nestedWindow),
            "Nested window drag handle should be blocked by top-hit titlebar container"
        )
        XCTAssertEqual(nestedBlockingOverlay.hitCount, 1)

        var nestedCaptureResult: Bool?
        let probe = PassThroughProbeView(frame: outerContainer.bounds)
        probe.autoresizingMask = [.width, .height]
        probe.onHitTest = {
            nestedCaptureResult = windowDragHandleShouldCaptureHit(point, in: nestedDragHandle, eventType: .leftMouseDown, eventWindow: nestedWindow)
        }
        outerContainer.addSubview(probe)

        _ = windowDragHandleShouldCaptureHit(point, in: outerDragHandle, eventType: .leftMouseDown, eventWindow: outerWindow)

        XCTAssertEqual(
            nestedCaptureResult,
            false,
            "Top-hit recursion in one window must not disable top-hit resolution in another window"
        )
        XCTAssertEqual(
            nestedBlockingOverlay.hitCount,
            2,
            "Nested window should resolve its own blocking sibling while another window is resolving hits"
        )
    }

    func testDragHandleRemainsStableWhenSiblingMutatesSubviewsDuringHitTest() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 36))
        let dragHandle = NSView(frame: container.bounds)
        container.addSubview(dragHandle)

        let mutatingSibling = MutatingSiblingView(frame: container.bounds)
        mutatingSibling.container = container
        container.addSubview(mutatingSibling)

        XCTAssertTrue(
            windowDragHandleShouldCaptureHit(NSPoint(x: 180, y: 18), in: dragHandle, eventType: .leftMouseDown),
            "Subview mutations during hit testing should not crash or break drag-handle capture"
        )
    }

    func testDragHandleSiblingHitTestReentrancyDoesNotCrash() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 36))
        let dragHandle = NSView(frame: container.bounds)
        container.addSubview(dragHandle)

        let reentrantSibling = ReentrantSiblingView(frame: container.bounds)
        reentrantSibling.dragHandle = dragHandle
        container.addSubview(reentrantSibling)

        // The outer call enters the sibling walk, which calls
        // reentrantSibling.hitTest(), which re-enters
        // windowDragHandleShouldCaptureHit. Without the re-entrancy guard
        // this would trigger a Swift exclusive-access violation (SIGABRT).
        let outerResult = windowDragHandleShouldCaptureHit(
            NSPoint(x: 110, y: 18), in: dragHandle, eventType: .leftMouseDown
        )
        XCTAssertTrue(outerResult, "Outer call should still capture when sibling returns nil")
        XCTAssertEqual(
            reentrantSibling.reenteredResult, false,
            "Re-entrant call should bail out (return false) instead of crashing"
        )
    }

    func testDragHandleTopHitResolutionSurvivesSameWindowReentrancy() {
        let point = NSPoint(x: 180, y: 18)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 36),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let container = NSView(frame: contentView.bounds)
        container.autoresizingMask = [.width, .height]
        contentView.addSubview(container)

        let dragHandle = ReentrantDragHandleView(frame: container.bounds)
        dragHandle.autoresizingMask = [.width, .height]
        container.addSubview(dragHandle)

        XCTAssertTrue(
            windowDragHandleShouldCaptureHit(point, in: dragHandle, eventType: .leftMouseDown, eventWindow: window),
            "Reentrant same-window top-hit resolution should not trigger exclusivity crashes"
        )
    }
}

#if DEBUG


@MainActor
final class DraggableFolderHitTests: XCTestCase {
    func testFolderHitTestReturnsContainerWhenInsideBounds() {
        let folderView = DraggableFolderNSView(directory: "/tmp")
        folderView.frame = NSRect(x: 0, y: 0, width: 16, height: 16)

        guard let hit = folderView.hitTest(NSPoint(x: 8, y: 8)) else {
            XCTFail("Expected folder icon to capture inside hit")
            return
        }
        XCTAssertTrue(hit === folderView)
    }

    func testFolderHitTestReturnsNilOutsideBounds() {
        let folderView = DraggableFolderNSView(directory: "/tmp")
        folderView.frame = NSRect(x: 0, y: 0, width: 16, height: 16)

        XCTAssertNil(folderView.hitTest(NSPoint(x: 20, y: 8)))
    }

    func testFolderIconDisablesWindowMoveBehavior() {
        let folderView = DraggableFolderNSView(directory: "/tmp")
        XCTAssertFalse(folderView.mouseDownCanMoveWindow)
    }
}


@MainActor
final class TitlebarLeadingInsetPassthroughViewTests: XCTestCase {
    func testLeadingInsetViewDoesNotParticipateInHitTesting() {
        let view = TitlebarLeadingInsetPassthroughView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        XCTAssertNil(view.hitTest(NSPoint(x: 20, y: 10)))
    }

    func testLeadingInsetViewCannotMoveWindowViaMouseDown() {
        let view = TitlebarLeadingInsetPassthroughView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        XCTAssertFalse(view.mouseDownCanMoveWindow)
    }

    func testMainWindowHostingViewCannotMoveWindowViaMouseDown() {
        let view = MainWindowHostingView(rootView: Color.clear)
        XCTAssertFalse(
            view.mouseDownCanMoveWindow,
            "Main content must never become an implicit AppKit window-drag region; explicit titlebar chrome owns app-window dragging"
        )
    }

    func testMainWindowDragBehaviorRequiresExplicitDragZones() {
        let window = CmuxMainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        window.isMovable = true
        window.isMovableByWindowBackground = true

        configureCmuxMainWindowDragBehavior(window)

        XCTAssertFalse(
            window.isMovable,
            "Main windows must not use native AppKit titlebar dragging because pane tabs live in the titlebar band"
        )
        XCTAssertFalse(window.isMovableByWindowBackground)

        let previous = withTemporaryWindowMovableEnabled(window: window) {
            XCTAssertTrue(window.isMovable)
        }

        XCTAssertEqual(previous, false)
        XCTAssertFalse(
            window.isMovable,
            "Explicit chrome drag zones may temporarily enable movement, but the main window must return to pane-tab-safe immovable state"
        )
    }
}


@Suite("Custom titlebar leading padding")
struct CustomTitlebarLeadingPaddingTests {
    @Test func hiddenSidebarUsesMinimumSidebarTitleInset() {
        #expect(
            ContentView.customTitlebarLeadingPadding(
                isFullScreen: false,
                isSidebarVisible: false,
                sidebarWidth: 216,
                minimumSidebarWidth: 216,
                titlebarLeadingInset: 82
            ) == 228
        )
    }

    @Test func minimumWidthVisibleSidebarMatchesHiddenSidebarTitleInset() {
        let hidden = ContentView.customTitlebarLeadingPadding(
            isFullScreen: false,
            isSidebarVisible: false,
            sidebarWidth: 216,
            minimumSidebarWidth: 216,
            titlebarLeadingInset: 82
        )
        let visible = ContentView.customTitlebarLeadingPadding(
            isFullScreen: false,
            isSidebarVisible: true,
            sidebarWidth: 216,
            minimumSidebarWidth: 216,
            titlebarLeadingInset: 82
        )

        #expect(visible == hidden)
    }

    @Test func widerSidebarPushesTitlebarContentRight() {
        let hidden = ContentView.customTitlebarLeadingPadding(
            isFullScreen: false,
            isSidebarVisible: false,
            sidebarWidth: 216,
            minimumSidebarWidth: 216,
            titlebarLeadingInset: 82
        )
        let visible = ContentView.customTitlebarLeadingPadding(
            isFullScreen: false,
            isSidebarVisible: true,
            sidebarWidth: 320,
            minimumSidebarWidth: 216,
            titlebarLeadingInset: 82
        )

        #expect(visible > hidden)
        #expect(visible == 332)
    }

    @Test func fullscreenHiddenSidebarKeepsCompactInset() {
        #expect(
            ContentView.customTitlebarLeadingPadding(
                isFullScreen: true,
                isSidebarVisible: false,
                sidebarWidth: 216,
                minimumSidebarWidth: 216,
                titlebarLeadingInset: 82
            ) == 8
        )
    }
}


@MainActor
final class FolderWindowMoveSuppressionTests: XCTestCase {
    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
    }

    func testSuppressionTracksMovableWindowWithoutChangingMovability() {
        let window = makeWindow()
        window.isMovable = true

        let depth = beginWindowDragSuppression(window: window)

        XCTAssertEqual(depth, 1)
        XCTAssertTrue(isWindowDragSuppressed(window: window))
        XCTAssertTrue(window.isMovable)
    }

    func testSuppressionTracksImmovableWindowWithoutChangingMovability() {
        let window = makeWindow()
        window.isMovable = false

        let depth = beginWindowDragSuppression(window: window)

        XCTAssertEqual(depth, 1)
        XCTAssertTrue(isWindowDragSuppressed(window: window))
        XCTAssertFalse(window.isMovable)
    }

    func testEndingSuppressionDoesNotRestoreStaleMovability() {
        let window = makeWindow()
        window.isMovable = false

        XCTAssertEqual(beginWindowDragSuppression(window: window), 1)
        XCTAssertFalse(window.isMovable)

        window.isMovable = true

        XCTAssertEqual(endWindowDragSuppression(window: window), 0)
        XCTAssertFalse(isWindowDragSuppressed(window: window))
        XCTAssertTrue(window.isMovable)
    }

    func testClearWindowDragSuppressionRemovesAllDepth() {
        let window = makeWindow()
        window.isMovable = false

        XCTAssertEqual(beginWindowDragSuppression(window: window), 1)
        XCTAssertEqual(beginWindowDragSuppression(window: window), 2)
        XCTAssertEqual(windowDragSuppressionDepth(window: window), 2)

        XCTAssertEqual(clearWindowDragSuppression(window: window), 0)
        XCTAssertEqual(windowDragSuppressionDepth(window: window), 0)
        XCTAssertFalse(window.isMovable)
    }

    func testClearWindowDragSuppressionFinishesActiveMoveSequence() {
        let window = makeWindow()
        window.isMovable = true

        XCTAssertEqual(
            beginWindowMoveSuppressionSequence(window: window, reason: .bonsplitPaneTabDrag),
            .bonsplitPaneTabDrag
        )
        XCTAssertFalse(window.isMovable)
        XCTAssertEqual(activeWindowMoveSuppressionSequenceReason(window: window), .bonsplitPaneTabDrag)

        XCTAssertEqual(clearWindowDragSuppression(window: window), 0)

        XCTAssertNil(activeWindowMoveSuppressionSequenceReason(window: window))
        XCTAssertEqual(windowDragSuppressionDepth(window: window), 0)
        XCTAssertFalse(isWindowDragSuppressed(window: window))
        XCTAssertTrue(window.isMovable)
    }

    func testWindowDragSuppressionDepthLifecycle() {
        let window = makeWindow()
        XCTAssertEqual(windowDragSuppressionDepth(window: window), 0)
        XCTAssertFalse(isWindowDragSuppressed(window: window))

        XCTAssertEqual(beginWindowDragSuppression(window: window), 1)
        XCTAssertEqual(windowDragSuppressionDepth(window: window), 1)
        XCTAssertTrue(isWindowDragSuppressed(window: window))

        XCTAssertEqual(endWindowDragSuppression(window: window), 0)
        XCTAssertEqual(windowDragSuppressionDepth(window: window), 0)
        XCTAssertFalse(isWindowDragSuppressed(window: window))
    }

    func testWindowDragSuppressionIsReferenceCounted() {
        let window = makeWindow()
        XCTAssertEqual(beginWindowDragSuppression(window: window), 1)
        XCTAssertEqual(beginWindowDragSuppression(window: window), 2)
        XCTAssertEqual(windowDragSuppressionDepth(window: window), 2)
        XCTAssertTrue(isWindowDragSuppressed(window: window))

        XCTAssertEqual(endWindowDragSuppression(window: window), 1)
        XCTAssertEqual(windowDragSuppressionDepth(window: window), 1)
        XCTAssertTrue(isWindowDragSuppressed(window: window))

        XCTAssertEqual(endWindowDragSuppression(window: window), 0)
        XCTAssertEqual(windowDragSuppressionDepth(window: window), 0)
        XCTAssertFalse(isWindowDragSuppressed(window: window))
    }

    func testTemporaryWindowMovableEnableRestoresImmovableWindow() {
        let window = makeWindow()
        window.isMovable = false

        let previous = withTemporaryWindowMovableEnabled(window: window) {
            XCTAssertTrue(window.isMovable)
        }

        XCTAssertEqual(previous, false)
        XCTAssertFalse(window.isMovable)
    }

    func testTemporaryWindowMovableEnablePreservesMovableWindow() {
        let window = makeWindow()
        window.isMovable = true

        let previous = withTemporaryWindowMovableEnabled(window: window) {
            XCTAssertTrue(window.isMovable)
        }

        XCTAssertEqual(previous, true)
        XCTAssertTrue(window.isMovable)
    }
}


@MainActor
final class WindowMoveSuppressionHitPathTests: XCTestCase {
    private func makeWindowWithContentView() -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = contentView
        return (window, contentView)
    }

    private func makeMouseEvent(type: NSEvent.EventType, location: NSPoint, window: NSWindow) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        ) else {
            fatalError("Failed to create \(type) mouse event")
        }
        return event
    }

    func testSuppressionHitPathRecognizesFolderView() {
        let folderView = DraggableFolderNSView(directory: "/tmp")
        XCTAssertTrue(shouldSuppressWindowMoveForFolderDrag(hitView: folderView))
    }

    func testSuppressionHitPathRecognizesDescendantOfFolderView() {
        let folderView = DraggableFolderNSView(directory: "/tmp")
        let child = NSView(frame: .zero)
        folderView.addSubview(child)
        XCTAssertTrue(shouldSuppressWindowMoveForFolderDrag(hitView: child))
    }

    func testSuppressionHitPathIgnoresUnrelatedViews() {
        XCTAssertFalse(shouldSuppressWindowMoveForFolderDrag(hitView: NSView(frame: .zero)))
        XCTAssertFalse(shouldSuppressWindowMoveForFolderDrag(hitView: nil))
    }

    func testSuppressionEventPathRecognizesFolderHitInsideWindow() {
        let (window, contentView) = makeWindowWithContentView()
        window.isMovable = true
        let folderView = DraggableFolderNSView(directory: "/tmp")
        folderView.frame = NSRect(x: 10, y: 10, width: 16, height: 16)
        contentView.addSubview(folderView)

        let event = makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 14, y: 14), window: window)

        XCTAssertTrue(shouldSuppressWindowMoveForFolderDrag(window: window, event: event))
    }

    func testSuppressionEventPathRejectsNonFolderAndNonMouseDownEvents() {
        let (window, contentView) = makeWindowWithContentView()
        window.isMovable = true
        let plainView = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        contentView.addSubview(plainView)

        let down = makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 20, y: 20), window: window)
        XCTAssertFalse(shouldSuppressWindowMoveForFolderDrag(window: window, event: down))

        let dragged = makeMouseEvent(type: .leftMouseDragged, location: NSPoint(x: 20, y: 20), window: window)
        XCTAssertFalse(shouldSuppressWindowMoveForFolderDrag(window: window, event: dragged))
    }

    func testBonsplitPaneTabMouseDownSuppressesWindowMove() {
        let (window, contentView) = makeWindowWithContentView()
        window.isMovable = true
        let tabRegion = FakeBonsplitTabItemRegionView(frame: NSRect(x: 20, y: 132, width: 240, height: 30))
        tabRegion.tabFrames = [CGRect(x: 8, y: 0, width: 96, height: 30)]
        contentView.addSubview(tabRegion)
        BonsplitTabItemHitRegionRegistry.register(tabRegion)
        defer { BonsplitTabItemHitRegionRegistry.unregister(tabRegion) }

        let tabPoint = tabRegion.convert(NSPoint(x: 28, y: 15), to: nil)
        let event = makeMouseEvent(type: .leftMouseDown, location: tabPoint, window: window)

        XCTAssertTrue(shouldSuppressWindowMoveForBonsplitPaneTabDrag(window: window, event: event))
        XCTAssertEqual(windowMoveSuppressionReason(window: window, event: event), .bonsplitPaneTabDrag)
    }

    func testBonsplitPaneTabDragSequenceKeepsWindowImmovableUntilMouseUp() {
        let (window, contentView) = makeWindowWithContentView()
        window.isMovable = true
        let tabRegion = FakeBonsplitTabItemRegionView(frame: NSRect(x: 20, y: 132, width: 240, height: 30))
        tabRegion.tabFrames = [CGRect(x: 8, y: 0, width: 96, height: 30)]
        contentView.addSubview(tabRegion)
        BonsplitTabItemHitRegionRegistry.register(tabRegion)
        defer {
            _ = finishWindowMoveSuppressionSequence(window: window)
            BonsplitTabItemHitRegionRegistry.unregister(tabRegion)
        }

        let tabPoint = tabRegion.convert(NSPoint(x: 28, y: 15), to: nil)
        let down = makeMouseEvent(type: .leftMouseDown, location: tabPoint, window: window)

        XCTAssertEqual(beginOrContinueWindowMoveSuppressionSequenceForEvent(window: window, event: down), .bonsplitPaneTabDrag)
        XCTAssertFalse(window.isMovable)
        XCTAssertTrue(isWindowDragSuppressed(window: window))
        XCTAssertEqual(activeWindowMoveSuppressionSequenceReason(window: window), .bonsplitPaneTabDrag)

        let draggedOutsideTab = makeMouseEvent(
            type: .leftMouseDragged,
            location: NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY),
            window: window
        )
        XCTAssertEqual(
            beginOrContinueWindowMoveSuppressionSequenceForEvent(window: window, event: draggedOutsideTab),
            .bonsplitPaneTabDrag
        )
        XCTAssertFalse(window.isMovable, "Window must remain immovable for the whole tab-drag mouse sequence")
        XCTAssertFalse(shouldFinishWindowMoveSuppressionSequenceAfterDispatch(window: window, event: draggedOutsideTab))

        let up = makeMouseEvent(type: .leftMouseUp, location: tabPoint, window: window)
        XCTAssertEqual(beginOrContinueWindowMoveSuppressionSequenceForEvent(window: window, event: up), .bonsplitPaneTabDrag)
        XCTAssertTrue(shouldFinishWindowMoveSuppressionSequenceAfterDispatch(window: window, event: up))
        XCTAssertEqual(finishWindowMoveSuppressionSequence(window: window), .bonsplitPaneTabDrag)
        XCTAssertTrue(window.isMovable)
        XCTAssertFalse(isWindowDragSuppressed(window: window))
        XCTAssertNil(activeWindowMoveSuppressionSequenceReason(window: window))
    }

    func testBonsplitPaneTabSuppressionRestoresImmovableMainWindow() {
        let (window, contentView) = makeWindowWithContentView()
        window.isMovable = false
        let tabRegion = FakeBonsplitTabItemRegionView(frame: NSRect(x: 20, y: 132, width: 240, height: 30))
        tabRegion.tabFrames = [CGRect(x: 8, y: 0, width: 96, height: 30)]
        contentView.addSubview(tabRegion)
        BonsplitTabItemHitRegionRegistry.register(tabRegion)
        defer {
            _ = finishWindowMoveSuppressionSequence(window: window)
            BonsplitTabItemHitRegionRegistry.unregister(tabRegion)
        }

        let tabPoint = tabRegion.convert(NSPoint(x: 28, y: 15), to: nil)
        let down = makeMouseEvent(type: .leftMouseDown, location: tabPoint, window: window)

        XCTAssertEqual(beginOrContinueWindowMoveSuppressionSequenceForEvent(window: window, event: down), .bonsplitPaneTabDrag)
        XCTAssertFalse(window.isMovable)
        XCTAssertEqual(finishWindowMoveSuppressionSequence(window: window), .bonsplitPaneTabDrag)
        XCTAssertFalse(
            window.isMovable,
            "Tab-drag suppression must not restore native AppKit window dragging when the main window baseline is immovable"
        )
    }

    func testNewMouseDownReevaluatesAfterStaleBonsplitPaneTabSuppression() {
        let (window, contentView) = makeWindowWithContentView()
        window.isMovable = true
        let tabRegion = FakeBonsplitTabItemRegionView(frame: NSRect(x: 20, y: 132, width: 240, height: 30))
        tabRegion.tabFrames = [CGRect(x: 8, y: 0, width: 96, height: 30)]
        contentView.addSubview(tabRegion)
        BonsplitTabItemHitRegionRegistry.register(tabRegion)
        defer {
            _ = finishWindowMoveSuppressionSequence(window: window)
            BonsplitTabItemHitRegionRegistry.unregister(tabRegion)
        }

        let tabPoint = tabRegion.convert(NSPoint(x: 28, y: 15), to: nil)
        let down = makeMouseEvent(type: .leftMouseDown, location: tabPoint, window: window)
        XCTAssertEqual(beginOrContinueWindowMoveSuppressionSequenceForEvent(window: window, event: down), .bonsplitPaneTabDrag)
        XCTAssertFalse(window.isMovable)

        let emptyChromePoint = tabRegion.convert(NSPoint(x: 180, y: 15), to: nil)
        let nextDown = makeMouseEvent(type: .leftMouseDown, location: emptyChromePoint, window: window)
        XCTAssertNil(
            beginOrContinueWindowMoveSuppressionSequenceForEvent(
                window: window,
                event: nextDown,
                pressedMouseButtons: 1
            ),
            "A fresh mouse-down must end stale tab suppression and re-check the actual hit target"
        )
        XCTAssertTrue(window.isMovable)
        XCTAssertFalse(isWindowDragSuppressed(window: window))
        XCTAssertNil(activeWindowMoveSuppressionSequenceReason(window: window))
    }

    func testBonsplitPaneTabSuppressionLeavesEmptyTabChromeDraggable() {
        let (window, contentView) = makeWindowWithContentView()
        window.isMovable = true
        let tabRegion = FakeBonsplitTabItemRegionView(frame: NSRect(x: 20, y: 132, width: 240, height: 30))
        tabRegion.tabFrames = [CGRect(x: 8, y: 0, width: 96, height: 30)]
        contentView.addSubview(tabRegion)
        BonsplitTabItemHitRegionRegistry.register(tabRegion)
        defer { BonsplitTabItemHitRegionRegistry.unregister(tabRegion) }

        let emptyChromePoint = tabRegion.convert(NSPoint(x: 180, y: 15), to: nil)
        let event = makeMouseEvent(type: .leftMouseDown, location: emptyChromePoint, window: window)

        XCTAssertFalse(shouldSuppressWindowMoveForBonsplitPaneTabDrag(window: window, event: event))
        XCTAssertNil(windowMoveSuppressionReason(window: window, event: event))
    }
}


final class FilePreviewDragPasteboardWriterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        FilePreviewDragRegistry.shared.discardAll()
        NSPasteboard(name: .drag).clearContents()
    }

    override func tearDown() {
        NSPasteboard(name: .drag).clearContents()
        FilePreviewDragRegistry.shared.discardAll()
        super.tearDown()
    }

    func testRegistrationIsPreparedWhenDragTypesAreRequested() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/example.txt").standardizedFileURL
        let writer = FilePreviewDragPasteboardWriter(
            filePath: fileURL.path,
            displayTitle: "example.txt"
        )
        let dragPasteboard = NSPasteboard(name: .drag)

        XCTAssertNil(FilePreviewDragPasteboardWriter.dragID(from: dragPasteboard))
        let writableTypes = writer.writableTypes(for: dragPasteboard)
        XCTAssertTrue(writableTypes.contains(.fileURL))
        let preparedDragID = try XCTUnwrap(FilePreviewDragPasteboardWriter.dragID(from: dragPasteboard))
        XCTAssertTrue(FilePreviewDragRegistry.shared.contains(id: preparedDragID))
        XCTAssertEqual(
            writer.pasteboardPropertyList(forType: .fileURL) as? String,
            fileURL.absoluteString
        )

        let filePreviewData = try XCTUnwrap(
            writer.pasteboardPropertyList(forType: DragOverlayRoutingPolicy.filePreviewTransferType) as? Data
        )
        let dragID = try XCTUnwrap(FilePreviewDragPasteboardWriter.dragID(from: filePreviewData))
        XCTAssertEqual(dragID, preparedDragID)
        XCTAssertTrue(FilePreviewDragRegistry.shared.contains(id: dragID))

        let bonsplitData = try XCTUnwrap(
            writer.pasteboardPropertyList(forType: FilePreviewDragPasteboardWriter.bonsplitTransferType) as? Data
        )
        XCTAssertEqual(FilePreviewDragPasteboardWriter.dragID(from: bonsplitData), dragID)
        XCTAssertEqual(dragPasteboard.data(forType: DragOverlayRoutingPolicy.filePreviewTransferType), filePreviewData)
        XCTAssertEqual(dragPasteboard.data(forType: FilePreviewDragPasteboardWriter.bonsplitTransferType), filePreviewData)
        XCTAssertEqual(dragPasteboard.string(forType: .fileURL), fileURL.absoluteString)

        FilePreviewDragPasteboardWriter.discardRegisteredDrag(from: dragPasteboard)

        XCTAssertFalse(FilePreviewDragRegistry.shared.contains(id: dragID))
    }

    func testRegistrySweepsExpiredDragEntries() {
        let start = Date(timeIntervalSince1970: 1_000)
        let oldID = FilePreviewDragRegistry.shared.register(
            FilePreviewDragEntry(filePath: "/tmp/old.txt", displayTitle: "old.txt"),
            now: start
        )
        XCTAssertTrue(FilePreviewDragRegistry.shared.contains(id: oldID, now: start.addingTimeInterval(30)))

        let newID = FilePreviewDragRegistry.shared.register(
            FilePreviewDragEntry(filePath: "/tmp/new.txt", displayTitle: "new.txt"),
            now: start.addingTimeInterval(61)
        )

        XCTAssertFalse(FilePreviewDragRegistry.shared.contains(id: oldID, now: start.addingTimeInterval(61)))
        XCTAssertTrue(FilePreviewDragRegistry.shared.contains(id: newID, now: start.addingTimeInterval(61)))
    }
}


final class BonsplitTabDragPayloadTests: XCTestCase {
    func testRejectsFilePreviewCompatibilityPayload() throws {
        let pasteboard = try makeBonsplitPayloadPasteboard(kind: "filePreview", includesFilePreviewTransferType: true)

        XCTAssertNil(
            BonsplitTabDragPayload.transfer(from: pasteboard),
            "Sidebar workspace drop targets should ignore file-preview drags instead of treating them as movable tabs"
        )
    }

    func testAcceptsRealFilePreviewTabPayload() throws {
        let pasteboard = try makeBonsplitPayloadPasteboard(kind: "filePreview")

        XCTAssertNotNil(
            BonsplitTabDragPayload.transfer(from: pasteboard),
            "Existing file-preview tabs should still move through normal Bonsplit tab drag paths"
        )
    }

    func testAcceptsRegularCurrentProcessTabPayload() throws {
        let pasteboard = try makeBonsplitPayloadPasteboard(kind: nil)

        XCTAssertNotNil(BonsplitTabDragPayload.transfer(from: pasteboard))
    }

    func testWorkspaceDropRoutingAcceptsTabTransferTypeOnly() {
        XCTAssertTrue(
            BonsplitTabDragPayload.canRouteWorkspaceDrop(
                pasteboardTypes: [DragOverlayRoutingPolicy.bonsplitTabTransferType]
            )
        )
    }

    func testWorkspaceDropRoutingRejectsFilePreviewCompatibilityTransfer() {
        XCTAssertFalse(
            BonsplitTabDragPayload.canRouteWorkspaceDrop(
                pasteboardTypes: [
                    DragOverlayRoutingPolicy.filePreviewTransferType,
                    DragOverlayRoutingPolicy.bonsplitTabTransferType,
                ]
            )
        )
    }

    private func makeBonsplitPayloadPasteboard(
        kind: String?,
        includesFilePreviewTransferType: Bool = false
    ) throws -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cmux.test.bonsplit.\(UUID().uuidString)"))
        pasteboard.clearContents()

        var tab: [String: Any] = ["id": UUID().uuidString]
        if let kind {
            tab["kind"] = kind
        }
        let payload: [String: Any] = [
            "tab": tab,
            "sourcePaneId": UUID().uuidString,
            "sourceProcessId": Int(ProcessInfo.processInfo.processIdentifier)
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(BonsplitTabDragPayload.typeIdentifier))
        if includesFilePreviewTransferType {
            pasteboard.setData(data, forType: DragOverlayRoutingPolicy.filePreviewTransferType)
        }
        return pasteboard
    }
}

@MainActor
final class TmuxWorkspacePaneOverlayTests: XCTestCase {
    func testTmuxWorkspacePaneOverlayModelTracksFlashReason() {
        let model = TmuxWorkspacePaneOverlayModel()
        let initialState = TmuxWorkspacePaneOverlayRenderState(
            workspaceId: UUID(),
            unreadRects: [],
            flashRect: CGRect(x: 10, y: 20, width: 300, height: 200),
            flashToken: 1,
            flashReason: .notificationArrival
        )
        let laterState = TmuxWorkspacePaneOverlayRenderState(
            workspaceId: initialState.workspaceId,
            unreadRects: [],
            flashRect: CGRect(x: 10, y: 20, width: 300, height: 200),
            flashToken: 2,
            flashReason: .navigation
        )

        model.apply(initialState)
        model.apply(laterState)

        XCTAssertEqual(model.flashReason, .navigation)
    }

    func testTmuxWorkspacePaneOverlayModelAnimatesFlashAfterWorkspaceSwitchBackWhenTokenChanges() {
        let model = TmuxWorkspacePaneOverlayModel()
        let firstWorkspaceId = UUID()
        let secondWorkspaceId = UUID()
        let firstFlashRect = CGRect(x: 10, y: 20, width: 300, height: 200)
        let flashDate = Date(timeIntervalSince1970: 42)

        model.apply(TmuxWorkspacePaneOverlayRenderState(
            workspaceId: firstWorkspaceId,
            unreadRects: [firstFlashRect],
            flashRect: firstFlashRect,
            flashToken: 0,
            flashReason: nil
        ))
        XCTAssertNil(model.flashStartedAt)

        model.apply(TmuxWorkspacePaneOverlayRenderState(
            workspaceId: secondWorkspaceId,
            unreadRects: [],
            flashRect: nil,
            flashToken: 0,
            flashReason: nil
        ))
        XCTAssertNil(model.flashStartedAt)

        model.apply(
            TmuxWorkspacePaneOverlayRenderState(
                workspaceId: firstWorkspaceId,
                unreadRects: [],
                flashRect: firstFlashRect,
                flashToken: 1,
                flashReason: .unreadIndicatorDismiss
            ),
            now: { flashDate }
        )

        XCTAssertEqual(model.flashStartedAt, flashDate)
        XCTAssertEqual(model.flashReason, .unreadIndicatorDismiss)
    }

    func testTmuxWorkspacePaneOverlayModelWaitsForFlashRectBeforeConsumingToken() {
        let model = TmuxWorkspacePaneOverlayModel()
        let firstWorkspaceId = UUID()
        let secondWorkspaceId = UUID()
        let firstFlashRect = CGRect(x: 10, y: 20, width: 300, height: 200)
        let flashDate = Date(timeIntervalSince1970: 42)

        model.apply(TmuxWorkspacePaneOverlayRenderState(
            workspaceId: firstWorkspaceId,
            unreadRects: [],
            flashRect: firstFlashRect,
            flashToken: 0,
            flashReason: nil
        ))
        model.apply(TmuxWorkspacePaneOverlayRenderState(
            workspaceId: secondWorkspaceId,
            unreadRects: [],
            flashRect: nil,
            flashToken: 0,
            flashReason: nil
        ))

        model.apply(TmuxWorkspacePaneOverlayRenderState(
            workspaceId: firstWorkspaceId,
            unreadRects: [],
            flashRect: nil,
            flashToken: 1,
            flashReason: .unreadIndicatorDismiss
        ))
        XCTAssertNil(model.flashStartedAt)

        model.apply(
            TmuxWorkspacePaneOverlayRenderState(
                workspaceId: firstWorkspaceId,
                unreadRects: [],
                flashRect: firstFlashRect,
                flashToken: 1,
                flashReason: .unreadIndicatorDismiss
            ),
            now: { flashDate }
        )

        XCTAssertEqual(model.flashStartedAt, flashDate)
        XCTAssertEqual(model.flashReason, .unreadIndicatorDismiss)
    }

    func testTmuxWorkspacePaneOverlayModelAnimatesFirstObservedFlashToken() {
        let model = TmuxWorkspacePaneOverlayModel()
        let workspaceId = UUID()
        let flashRect = CGRect(x: 10, y: 20, width: 300, height: 200)
        let flashDate = Date(timeIntervalSince1970: 42)

        model.apply(
            TmuxWorkspacePaneOverlayRenderState(
                workspaceId: workspaceId,
                unreadRects: [],
                flashRect: flashRect,
                flashToken: 1,
                flashReason: .unreadIndicatorDismiss
            ),
            now: { flashDate }
        )

        XCTAssertEqual(model.flashStartedAt, flashDate)
        XCTAssertEqual(model.flashReason, .unreadIndicatorDismiss)
    }

    func testTmuxWorkspacePaneOverlayModelWaitsForRectBeforeFirstObservedFlashToken() {
        let model = TmuxWorkspacePaneOverlayModel()
        let workspaceId = UUID()
        let flashRect = CGRect(x: 10, y: 20, width: 300, height: 200)
        let flashDate = Date(timeIntervalSince1970: 42)

        model.apply(TmuxWorkspacePaneOverlayRenderState(
            workspaceId: workspaceId,
            unreadRects: [],
            flashRect: nil,
            flashToken: 1,
            flashReason: .unreadIndicatorDismiss
        ))
        XCTAssertNil(model.flashStartedAt)

        model.apply(
            TmuxWorkspacePaneOverlayRenderState(
                workspaceId: workspaceId,
                unreadRects: [],
                flashRect: flashRect,
                flashToken: 1,
                flashReason: .unreadIndicatorDismiss
            ),
            now: { flashDate }
        )

        XCTAssertEqual(model.flashStartedAt, flashDate)
        XCTAssertEqual(model.flashReason, .unreadIndicatorDismiss)
    }

    func testAllFlashReasonsUseNotificationRingAccent() {
        let reasons: [WorkspaceAttentionFlashReason] = [
            .navigation,
            .notificationArrival,
            .notificationDismiss,
            .unreadIndicatorDismiss,
            .debug,
        ]

        for reason in reasons {
            XCTAssertEqual(
                WorkspaceAttentionCoordinator.flashStyle(for: reason).accent,
                WorkspaceAttentionCoordinator.notificationRingStyle.accent
            )
        }
    }

    func testFocusFlashUsesNotificationRingColor() {
        XCTAssertEqual(
            WorkspaceAttentionCoordinator.flashStyle(for: .navigation).accent.strokeColor.hexString(),
            WorkspaceAttentionCoordinator.notificationRingStyle.accent.strokeColor.hexString()
        )
    }

    func testTmuxWorkspacePaneExactRectReturnsContentRelativeFrameForDescendantView() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }

        guard let contentView = window.contentView else {
            XCTFail("Expected contentView")
            return
        }

        let targetView = NSView(frame: NSRect(x: 120, y: 48, width: 300, height: 200))
        contentView.addSubview(targetView)

        XCTAssertEqual(
            ContentView.tmuxWorkspacePaneExactRect(for: targetView, in: contentView),
            CGRect(x: 120, y: 48, width: 300, height: 200)
        )
    }
}

@MainActor
final class ApplicationAccessibilityHierarchyCacheTests: XCTestCase {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        return window
    }

    private func assertWindowsEqual(_ actual: Any?, _ expected: [NSWindow], file: StaticString = #filePath, line: UInt = #line) {
        guard let actualWindows = actual as? [NSWindow] else {
            XCTFail("Expected NSWindow array", file: file, line: line)
            return
        }
        guard actualWindows.count == expected.count else {
            XCTFail("Expected \(expected.count) windows, got \(actualWindows.count)", file: file, line: line)
            return
        }
        for (lhs, rhs) in zip(actualWindows, expected) {
            XCTAssertTrue(lhs === rhs, file: file, line: line)
        }
    }

    func testRepeatedWindowsQueriesReuseSingleHierarchyBuildUntilStateChanges() {
        let firstWindow = makeWindow()
        let secondWindow = makeWindow()
        defer {
            firstWindow.orderOut(nil)
            secondWindow.orderOut(nil)
        }

        let cache = CmuxApplicationAccessibilityHierarchyCache()
        let state = CmuxApplicationAccessibilityHierarchyCache.StateToken(windows: [firstWindow, secondWindow])
        var buildCount = 0

        let firstValue = cache.value(for: .windows, stateToken: state) {
            buildCount += 1
            return .init(windows: [firstWindow, secondWindow])
        }
        let secondValue = cache.value(for: .windows, stateToken: state) {
            XCTFail("Expected cached snapshot for repeated state")
            return .init(windows: [])
        }

        assertWindowsEqual(firstValue, [firstWindow, secondWindow])
        assertWindowsEqual(secondValue, [firstWindow, secondWindow])
        XCTAssertEqual(buildCount, 1, "Expected a single hierarchy build for repeated AX queries with no invalidation")
    }

    func testChangedStateTokenInvalidatesCachedHierarchySnapshot() {
        let window = makeWindow()
        let otherWindow = makeWindow()
        defer {
            window.orderOut(nil)
            otherWindow.orderOut(nil)
        }

        let cache = CmuxApplicationAccessibilityHierarchyCache()
        let initialState = CmuxApplicationAccessibilityHierarchyCache.StateToken(windows: [window])
        let updatedState = CmuxApplicationAccessibilityHierarchyCache.StateToken(windows: [window, otherWindow])
        var buildCount = 0

        _ = cache.value(for: .windows, stateToken: initialState) {
            buildCount += 1
            return .init(windows: [window])
        }
        let updatedWindowsValue = cache.value(for: .windows, stateToken: updatedState) {
            buildCount += 1
            return .init(windows: [window, otherWindow])
        }

        assertWindowsEqual(updatedWindowsValue, [window, otherWindow])
        XCTAssertEqual(buildCount, 2, "Expected the cache to rebuild once after the hierarchy token changes")
    }

    func testNonWindowsAttributesStayPassthrough() {
        let cache = CmuxApplicationAccessibilityHierarchyCache()

        for attribute: NSAccessibility.Attribute in [.children, .visibleChildren, .mainWindow, .focusedWindow] {
            switch cache.resolve(attribute: attribute, application: NSApp) {
            case .passthrough:
                break
            case .handled:
                XCTFail("Expected \(attribute.rawValue) to fall back to AppKit")
            }
        }
    }

    func testWindowCloseNotificationInvalidatesCache() {
        let window = makeWindow()
        defer { window.orderOut(nil) }

        let center = NotificationCenter()
        let cache = CmuxApplicationAccessibilityHierarchyCache(notificationCenter: center)
        let state = CmuxApplicationAccessibilityHierarchyCache.StateToken(windows: [window])
        var buildCount = 0

        _ = cache.value(for: .windows, stateToken: state) {
            buildCount += 1
            return .init(windows: [window])
        }
        center.post(name: NSWindow.willCloseNotification, object: window)
        _ = cache.value(for: .windows, stateToken: state) {
            buildCount += 1
            return .init(windows: [window])
        }

        XCTAssertEqual(buildCount, 2, "Expected NSWindow.willCloseNotification to invalidate the cache")
    }
}
#endif
