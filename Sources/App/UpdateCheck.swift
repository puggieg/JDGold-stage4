import Cocoa

extension AppDelegate {
    @MainActor
    func performUpdateCheck() async {
        // FIX(B5): App 的版本以打包后的 Info.plist 为准，不再硬编码。
        guard !UPDATE_REPO.isEmpty else { return }
        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !currentVersion.isEmpty else {
            appLog("更新", "Info.plist 缺少 CFBundleShortVersionString")
            return
        }
        let repoURL = "https://api.github.com/repos/\(UPDATE_REPO)/releases/latest"
        guard let url = URL(string: repoURL) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw NSError(domain: "JDGold", code: 5, userInfo: [NSLocalizedDescriptionKey: "更新接口 HTTP 状态异常"])
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tagName = json["tag_name"] as? String {
                let latestVersion = tagName.replacingOccurrences(of: "v", with: "")
                if latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                    let alert = NSAlert()
                    alert.messageText = "发现新版本"
                    alert.informativeText = "当前版本: v\(currentVersion)\n最新版本: v\(latestVersion)\n\n是否前往下载？"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "前往下载")
                    alert.addButton(withTitle: "稍后再说")
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let downloadURL = URL(string: "https://github.com/\(UPDATE_REPO)/releases/latest") {
                            NSWorkspace.shared.open(downloadURL)
                        }
                    }
                } else {
                    let alert = NSAlert()
                    alert.messageText = "已是最新版本"
                    alert.informativeText = "当前版本 v\(currentVersion) 已是最新。"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "好")
                    alert.runModal()
                }
            }
            else { appLog("更新", "更新响应缺少 tag_name") }
        } catch { appLog("更新", "检查失败：\(error.localizedDescription)") }
    }

}
