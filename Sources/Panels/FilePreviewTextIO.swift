import AppKit

// Text load/save and zoom-interaction helpers shared by the markdown raw-text
// editor. Extracted from the (deleted) FilePreviewPanel so MarkdownPanel and
// FilePreviewTextEditor keep compiling after the file-preview panel was removed.

enum FilePreviewTextLoader {
    static let maximumLoadedTextBytes: UInt64 = 16 * 1024 * 1024

    enum Result: Sendable {
        case loaded(content: String, encoding: String.Encoding)
        case unavailable
    }

    static func load(url: URL) async -> Result {
        await Task.detached(priority: .userInitiated) {
            loadSynchronously(url: url)
        }.value
    }

    static func loadSynchronously(url: URL) -> Result {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .unavailable
        }
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize >= 0,
              UInt64(fileSize) <= maximumLoadedTextBytes else {
            return .unavailable
        }

        do {
            let data = try Data(contentsOf: url)
            guard let decoded = decodeText(data) else {
                return .unavailable
            }
            return .loaded(content: decoded.content, encoding: decoded.encoding)
        } catch {
            return .unavailable
        }
    }

    private static func decodeText(_ data: Data) -> (content: String, encoding: String.Encoding)? {
        if let decoded = String(data: data, encoding: .utf8) {
            return (decoded, .utf8)
        }
        if let decoded = String(data: data, encoding: .utf16) {
            return (decoded, .utf16)
        }
        if let decoded = String(data: data, encoding: .isoLatin1) {
            return (decoded, .isoLatin1)
        }
        return nil
    }
}

enum FilePreviewTextSaver {
    enum Result: Sendable {
        case saved
        case failed(fileExists: Bool)
    }

    static func save(content: String, to url: URL, encoding: String.Encoding) async -> Result {
        await Task.detached(priority: .userInitiated) {
            guard let data = content.data(using: encoding) else {
                return .failed(fileExists: FileManager.default.fileExists(atPath: url.path))
            }

            do {
                try data.write(to: url, options: [])
                return .saved
            } catch {
                return .failed(fileExists: FileManager.default.fileExists(atPath: url.path))
            }
        }.value
    }
}

enum FilePreviewInteraction {
    static let zoomStep: CGFloat = 1.25

    static func hasZoomModifier(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.option) || flags.contains(.command)
    }

    static func zoomFactor(forScroll event: NSEvent) -> CGFloat {
        let rawDelta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
        let normalizedDelta = event.hasPreciseScrollingDeltas ? rawDelta : rawDelta * 8
        let factor = pow(1.0025, normalizedDelta)
        guard factor.isFinite else { return 1 }
        return min(max(factor, 0.2), 5.0)
    }
}
