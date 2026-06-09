import AppKit

struct ShortcutEventFocusContext {
    let markdownPanel: MarkdownPanel?
    let rightSidebarFocused: Bool
}

struct ShortcutEventFocusContextCache {
    let event: NSEvent
    let context: ShortcutEventFocusContext
}

extension KeyboardShortcutSettings.Action {
    enum ShortcutContext: Equatable {
        case application
        case nonBrowserPanel
        case markdownPanel
        case rightSidebarFocus

        var isAlwaysAvailable: Bool {
            self == .application
        }

        func isAvailable(focusedMarkdownPanel: Bool, rightSidebarFocused: Bool) -> Bool {
            switch self {
            case .application:
                return true
            case .nonBrowserPanel:
                return !rightSidebarFocused
            case .markdownPanel:
                return focusedMarkdownPanel
            case .rightSidebarFocus:
                return rightSidebarFocused
            }
        }

        func isAvailable(_ context: ShortcutEventFocusContext) -> Bool {
            isAvailable(
                focusedMarkdownPanel: context.markdownPanel != nil,
                rightSidebarFocused: context.rightSidebarFocused
            )
        }

        func overlaps(_ other: ShortcutContext) -> Bool {
            if self == .application || other == .application {
                return true
            }
            if self == other {
                return true
            }
            // A focused markdown viewer also satisfies `.nonBrowserPanel`, so the
            // two contexts can be active at the same time. Treat them as
            // overlapping so shortcut conflict detection rejects a chord bound to
            // both a markdown-zoom action and a non-browser action.
            if (self == .markdownPanel && other == .nonBrowserPanel) ||
                (self == .nonBrowserPanel && other == .markdownPanel) {
                return true
            }
            return false
        }
    }

    var shortcutContext: ShortcutContext {
        switch self {
        case .switchRightSidebarToFiles, .switchRightSidebarToFind, .switchRightSidebarToSessions, .switchRightSidebarToFeed, .switchRightSidebarToDock:
            return .rightSidebarFocus
        case .renameTab, .renameWorkspace, .sendCtrlFToTerminal:
            return .nonBrowserPanel
        case .markdownZoomIn, .markdownZoomOut, .markdownZoomReset:
            return .markdownPanel
        default:
            return .application
        }
    }
}

extension AppDelegate {
    func shortcutEventMarkdownPanel(_ event: NSEvent) -> MarkdownPanel? {
        shortcutEventFocusContext(event).markdownPanel
    }

    func shortcutEventFocusContext(_ event: NSEvent) -> ShortcutEventFocusContext {
        if let cache = shortcutEventFocusContextCache, cache.event === event {
            return cache.context
        }

        let shortcutWindow = shortcutResolvedEventWindow(event) ?? NSApp.keyWindow ?? NSApp.mainWindow
        let context = ShortcutEventFocusContext(
            markdownPanel: shortcutFocusedMarkdownPanel(in: shortcutWindow),
            rightSidebarFocused: false
        )
        shortcutEventFocusContextCache = ShortcutEventFocusContextCache(event: event, context: context)
        return context
    }

    private func shortcutFocusedMarkdownPanel(in window: NSWindow?) -> MarkdownPanel? {
        // `focusedMarkdownPanel` is already gated to preview mode, where the
        // rendered viewer responds to zoom (the raw text editor does not).
        if let window {
            guard let context = mainWindowContexts[ObjectIdentifier(window)] ??
                mainWindowContexts.values.first(where: { $0.window === window }) else {
                return nil
            }
            return context.tabManager.focusedMarkdownPanel
        }

        return tabManager?.focusedMarkdownPanel
    }

    func clearShortcutEventFocusContextCache(for event: NSEvent) {
        if shortcutEventFocusContextCache?.event === event {
            shortcutEventFocusContextCache = nil
        }
    }

    private func shortcutResolvedEventWindow(_ event: NSEvent) -> NSWindow? {
        if let window = event.window {
            return window
        }
        guard event.windowNumber > 0 else { return nil }
        return NSApp.window(withWindowNumber: event.windowNumber)
    }
}
