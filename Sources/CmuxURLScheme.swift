import Foundation

/// Resolves the app's registered custom URL scheme (`cmux://`,
/// `cmux-dev://`, or `cmux-nightly://`) used by deep-link routing —
/// workspace/pane/surface links and the SSH-URL handler.
///
/// This previously lived in the (now-removed) cloud auth environment as
/// `AuthEnvironment.callbackScheme`; the name is kept as a thin alias so
/// the deep-link call sites continue to resolve. Nothing here touches
/// cloud accounts — it is purely the local URL-scheme constant.
enum AuthEnvironment {
    static var callbackScheme: String {
        let environment = ProcessInfo.processInfo.environment
        if let overridden = environment["CMUX_AUTH_CALLBACK_SCHEME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !overridden.isEmpty {
            return overridden
        }
        #if DEBUG
        // Debug and tagged dev builds register cmux-dev:// so they can coexist
        // with the installed stable app.
        return "cmux-dev"
        #else
        if Bundle.main.bundleIdentifier == "com.cmuxterm.app.nightly" {
            return "cmux-nightly"
        }
        return "cmux"
        #endif
    }
}
