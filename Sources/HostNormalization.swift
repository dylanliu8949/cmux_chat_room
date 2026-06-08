import Foundation

/// 主机名规范化工具。原先作为 `BrowserInsecureHTTPSettings` 的一部分定义在 `BrowserPanel.swift`，
/// 浏览器删除后下沉为独立类型——它与浏览器无关（终端链接校验、远程 loopback 别名解析都用它），
/// 只是恰好曾与浏览器的不安全 HTTP 白名单同处一文件。
enum HostNormalization {
    /// 从任意原始输入（URL、`host:port`、带 scheme 的串、IPv6 字面量等）提取并规范化主机名。
    /// 无法解析出非空主机时返回 `nil`。
    static func normalizeHost(_ rawHost: String) -> String? {
        var value = rawHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !value.isEmpty else { return nil }

        if let parsed = URL(string: value)?.host {
            return trimHost(parsed)
        }

        if let schemeRange = value.range(of: "://") {
            value = String(value[schemeRange.upperBound...])
        }

        if let slash = value.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            value = String(value[..<slash])
        }

        if value.hasPrefix("[") {
            if let closing = value.firstIndex(of: "]") {
                value = String(value[value.index(after: value.startIndex)..<closing])
            } else {
                value.removeFirst()
            }
        } else if let colon = value.lastIndex(of: ":"),
                  value[value.index(after: colon)...].allSatisfy(\.isNumber),
                  value.filter({ $0 == ":" }).count == 1 {
            value = String(value[..<colon])
        }

        return trimHost(value)
    }

    private static func trimHost(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !trimmed.isEmpty else { return nil }

        // Canonicalize IDN entries (e.g. bücher.example -> xn--bcher-kva.example)
        // so host comparisons stay consistent with `URL.host`.
        if let canonicalized = URL(string: "https://\(trimmed)")?.host {
            return canonicalized
        }

        return trimmed
    }
}
