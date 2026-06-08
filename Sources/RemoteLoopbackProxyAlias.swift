import Foundation

enum RemoteLoopbackProxyAlias {
    static let aliasHost = "cmux-loopback.localtest.me"

    static let canonicalLoopbackHost = "localhost"
    static let exactLoopbackHosts: Set<String> = [
        canonicalLoopbackHost,
        "127.0.0.1",
        "::1",
        "0.0.0.0",
    ]

    static func isLoopbackHost(_ host: String) -> Bool {
        guard let normalizedHost = HostNormalization.normalizeHost(host) else {
            return false
        }
        return exactLoopbackHosts.contains(normalizedHost)
            || normalizedHost.hasSuffix(".\(canonicalLoopbackHost)")
    }

    static func browserAliasHost(forLoopbackHost host: String, aliasHost: String) -> String {
        localhostFamilyAliasHost(forLoopbackHost: host, aliasHost: aliasHost) ?? aliasHost
    }

    static func localhostFamilyHost(forAliasHost host: String, aliasHost: String) -> String? {
        guard let normalizedHost = HostNormalization.normalizeHost(host),
              let normalizedAlias = HostNormalization.normalizeHost(aliasHost) else {
            return nil
        }
        if normalizedHost == normalizedAlias {
            return canonicalLoopbackHost
        }

        let suffix = ".\(normalizedAlias)"
        guard normalizedHost.hasSuffix(suffix) else { return nil }
        let prefix = String(normalizedHost.dropLast(suffix.count))
        guard !prefix.isEmpty else { return nil }
        return "\(prefix).\(canonicalLoopbackHost)"
    }

    static func localhostFamilyAliasHost(forLoopbackHost host: String, aliasHost: String) -> String? {
        guard let normalizedHost = HostNormalization.normalizeHost(host) else { return nil }
        if normalizedHost == canonicalLoopbackHost {
            return aliasHost
        }

        let suffix = ".\(canonicalLoopbackHost)"
        guard normalizedHost.hasSuffix(suffix) else { return nil }
        let prefix = String(normalizedHost.dropLast(suffix.count))
        guard !prefix.isEmpty else { return nil }
        return "\(prefix).\(aliasHost)"
    }
}

/// 远程 workspace 的本地端口代理端点（host:port）。原先随浏览器面板定义，浏览器删除后
/// 下沉至此，仅供远程代理 broker 使用，会随 remote（Phase 8）一并删除。
struct BrowserProxyEndpoint: Equatable {
    let host: String
    let port: Int
}
