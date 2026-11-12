import Foundation

actor BarkNotificationService {
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()
    func send(key: String?, query: String?, title: String, body: String) async -> String {
        guard let key = key, !key.isEmpty else { return "尚未绑定 Bark，请先保存链接。" }
        // FIX(B9): 所有路径段只允许 alphanumerics，避免 / ? # & 改变 URL 结构。
        guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return "推送内容编码失败。" }
        var address = "https://api.day.app/\(encodedKey)/\(encodedTitle)/\(encodedBody)"
        // 所有推送（含测试推送）统一归到 Bark 的 Gold Monitor 分组，保留用户原有 level/call 参数。
        address += "?\(BarkLinkParser.groupedQuery(query))"
        guard let url = URL(string: address) else { return "推送链接无效。" }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["code"] as? Int == 200 else {
                appLog("Bark", "推送失败：HTTP 或业务状态异常")
                return "发送失败，请检查 Key 和网络后重试。"
            }
            appLog("Bark", "服务端已接受推送")
            return "Bark 服务端已接受，请查看手机确认收到。"
        } catch {
            // 不输出 localizedDescription，避免系统错误带出包含 Key 的请求 URL。
            appLog("Bark", "请求失败，错误代码 \((error as NSError).code)")
            return "发送失败，网络错误 \((error as NSError).code)。"
        }
    }
}
