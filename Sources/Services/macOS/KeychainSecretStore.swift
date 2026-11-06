#if SWIFT_PACKAGE
import GoldPriceCore
#endif
import Foundation
import Security

struct KeychainError: Error { let status: OSStatus }
struct KeychainSecretStore: SecretStore {
    let service: String
    private let account = "BarkKey"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw CredentialError.verificationFailed }
        return value
    }
    func save(_ value: String) throws {
        let changed = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(query as CFDictionary, changed as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = Data(value.utf8)
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
// Security 操作是同步的；在 actor 中执行，避免阻塞 AppKit 主线程。
actor BarkCredentialService {
    private let credentials: BarkCredentials
    init(service: String) {
        // 在服务内部获取偏好，不把非 Sendable 的 UserDefaults 从 UI 跨 actor 传入。
        credentials = BarkCredentials(secrets: KeychainSecretStore(service: service), defaults: .standard)
    }
    func load() throws -> String? { try credentials.loadAndMigrate() }
    func save(_ value: String?) throws { try credentials.save(value) }
}
