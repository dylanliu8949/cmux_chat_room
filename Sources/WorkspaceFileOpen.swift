import Bonsplit
import Foundation

extension Workspace {
    /// Opens file paths in the workspace. With the in-app file-preview panel removed,
    /// only markdown files open as surfaces; other file types are ignored here (the
    /// file explorer offers "Open Externally" / "Reveal in Finder" for those).
    @discardableResult
    func openFileSurfaces(
        inPane paneId: PaneID,
        filePaths: [String],
        focus: Bool? = nil,
        targetIndex: Int? = nil,
        reuseExisting: Bool = false
    ) -> [any Panel] {
        let shouldFocusNewTabs = focus ?? (bonsplitController.focusedPaneId == paneId)
        var nextIndex = targetIndex
        var openedPanels: [any Panel] = []

        for filePath in filePaths {
            guard MarkdownPanelFileLinkResolver.isMarkdownPathLike(filePath) else { continue }
            let panel: (any Panel)?
            if reuseExisting {
                panel = openOrFocusMarkdownSurface(
                    inPane: paneId,
                    filePath: filePath,
                    focus: shouldFocusNewTabs
                )
            } else {
                panel = newMarkdownSurface(
                    inPane: paneId,
                    filePath: filePath,
                    focus: shouldFocusNewTabs,
                    targetIndex: nextIndex
                )
            }

            if let panel {
                openedPanels.append(panel)
                if let index = nextIndex {
                    nextIndex = index + 1
                }
            }
        }

        return openedPanels
    }
}
