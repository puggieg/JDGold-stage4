import Foundation

public struct BarkLink: Equatable {
    public let key: String
    public let query: String?
    public let level: String?
    public let continuousRing: Bool
    public var maskedKey: String { "••••" + String(key.suffix(4)) }
}
public enum BarkLinkError: Error, CustomStringConvertible {
    case invalidLink, invalidKey, invalidParameters
    public var description: String {
        switch self {
        case .invalidLink: return "请粘贴 https://api.day.app/ 开头的 Bark 链接或单独的 Key。"
        case .invalidKey: return "Key 只能包含英文字母、数字、下划线和短横线。"
        case .invalidParameters: return "level 或 call 参数无效或重复，请检查链接。"
        }
    }
}
public enum BarkLinkParser {
    // 本程序发出的所有推送都归到 Bark 的「Gold Monitor」分组；空格按 URL 规则编码。
    public static let notificationGroup = "Gold Monitor"
    public static let notificationGroupQuery = "group=Gold%20Monitor"

    // 保留用户链接里的原有参数（level/call 等），去掉任何已有 group，再强制加上本程序分组。
    // 纯函数，不改动持久化的原始 query。
    public static func groupedQuery(_ raw: String?) -> String {
        var kept: [String] = []
        for part in (raw ?? "").split(separator: "&", omittingEmptySubsequences: true) {
            let name = part.split(separator: "=", maxSplits: 1).first.map { String($0).lowercased() } ?? ""
            if name != "group" { kept.append(String(part)) }
        }
        kept.append(notificationGroupQuery)
        return kept.joined(separator: "&")
    }

    public static func parse(_ raw: String) throws -> BarkLink {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var key = text; var query: String?; var items: [URLQueryItem] = []
        if text.contains("://") {
            guard let url = URLComponents(string: text), url.scheme == "https", url.host == "api.day.app",
                  url.port == nil, url.user == nil, url.password == nil, url.fragment == nil,
                  let first = url.percentEncodedPath.split(separator: "/").first,
                  let decoded = String(first).removingPercentEncoding else { throw BarkLinkError.invalidLink }
            key = decoded; query = url.percentEncodedQuery; items = url.queryItems ?? []
        }
        guard key.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw BarkLinkError.invalidKey }
        let levels = items.filter { $0.name == "level" }; let calls = items.filter { $0.name == "call" }
        guard levels.count <= 1, calls.count <= 1 else { throw BarkLinkError.invalidParameters }
        let level = levels.first?.value
        if let level = level, !["active", "passive", "timeSensitive", "critical"].contains(level) { throw BarkLinkError.invalidParameters }
        if let call = calls.first, call.value != "1" { throw BarkLinkError.invalidParameters }
        return BarkLink(key: key, query: query, level: level, continuousRing: calls.first?.value == "1")
    }
}
