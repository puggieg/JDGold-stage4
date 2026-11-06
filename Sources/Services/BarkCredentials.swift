import Foundation

public protocol SecretStore {
    func read() throws -> String?
    func save(_ value: String) throws
    func delete() throws
}
public enum CredentialError: Error { case verificationFailed }
// 在测试中使用内存 SecretStore，真实 SecretStore 在 macOS 中由 Security 实现。
public final class BarkCredentials {
    private let secrets: any SecretStore
    private let defaults: UserDefaults
    public init(secrets: any SecretStore, defaults: UserDefaults) { self.secrets = secrets; self.defaults = defaults }
    public func loadAndMigrate() throws -> String? {
        if let current = try secrets.read(), !current.isEmpty {
            // 新钥匙串值优先，避免旧明文覆盖后来绑定的 Key。
            defaults.removeObject(forKey: "userBarkKey")
            return current
        }
        guard let old = defaults.string(forKey: "userBarkKey"), !old.isEmpty else { return nil }
        try secrets.save(old)
        guard try secrets.read() == old else { throw CredentialError.verificationFailed }
        // 确认成功写入并读回后才删除明文；失败时原配置仍在。
        defaults.removeObject(forKey: "userBarkKey")
        return old
    }
    public func save(_ value: String?) throws {
        if let value = value, !value.isEmpty {
            try secrets.save(value)
            guard try secrets.read() == value else { throw CredentialError.verificationFailed }
        } else { try secrets.delete() }
        defaults.removeObject(forKey: "userBarkKey")
    }
}
