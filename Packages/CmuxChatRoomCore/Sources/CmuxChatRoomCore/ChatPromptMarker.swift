import Foundation

/// Embeds and recovers the hidden ``ChatRequestID`` correlation token in an injected prompt.
///
/// The token is appended as a single trailing metadata line that survives verbatim in the agent's
/// `toolInputJSON`, is recovered at `prompt-submit`, and is stripped before any channel display or
/// forward. It is the sole correlation mechanism — there is no exact-text or FIFO-only fallback.
///
/// ```swift
/// let injected = ChatPromptMarker.inject(requestID, into: "review this")
/// let (id, clean) = ChatPromptMarker.extract(from: injected) // id == requestID, clean == "review this"
/// ```
public enum ChatPromptMarker {
    private static let prefix = "<!-- cmux-chat-request:"
    private static let suffix = " -->"

    /// Appends a non-displayed token encoding `id` after `body`.
    public static func inject(_ id: ChatRequestID, into body: String) -> String {
        "\(body)\n\n\(prefix)\(id.raw.uuidString)\(suffix)"
    }

    /// Recovers the ``ChatRequestID`` (if present) and returns the body with the marker line removed.
    ///
    /// Only a marker that parses to a valid UUID matches, so a body that merely mentions the token
    /// text is not a false positive.
    public static func extract(from rawPrompt: String) -> (ChatRequestID?, cleaned: String) {
        guard let prefixRange = rawPrompt.range(of: prefix, options: .backwards),
              let suffixRange = rawPrompt.range(of: suffix, range: prefixRange.upperBound..<rawPrompt.endIndex)
        else {
            return (nil, rawPrompt)
        }
        let uuidString = String(rawPrompt[prefixRange.upperBound..<suffixRange.lowerBound])
        guard let uuid = UUID(uuidString: uuidString) else {
            return (nil, rawPrompt)
        }
        var cleaned = String(rawPrompt[rawPrompt.startIndex..<prefixRange.lowerBound])
        while cleaned.hasSuffix("\n") || cleaned.hasSuffix(" ") || cleaned.hasSuffix("\t") {
            cleaned.removeLast()
        }
        return (ChatRequestID(raw: uuid), cleaned)
    }
}
