import Foundation
import LocalAuthentication
import Security

enum KeychainError: LocalizedError {
    case unhandled(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            "Keychain operation failed with status \(status)."
        case .invalidData:
            "The Keychain item did not contain valid text data."
        }
    }
}

struct ProviderKeychainCredentials: Sendable {
    let apiKey: String
    let aliyunAccessKeyID: String?
    let aliyunAccessKeySecret: String?
}

@MainActor
final class KeychainService {
    static let shared = KeychainService()

    /// How long read secrets stay in memory after the first load.
    var unlockSessionDuration: TimeInterval = 60 * 60

    private let service = "com.llmvault.provider-keys"
    private var memoryCache: [String: String] = [:]
    private var cacheValidUntil: Date?

    private init() {}

    var isUnlockSessionActive: Bool {
        guard let cacheValidUntil else { return false }
        return Date() < cacheValidUntil
    }

    func beginUnlockSession() {
        // Keys use kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly and do not require
        // an interactive LAContext. Session caching is handled in memory only.
    }

    func lockSession() {
        memoryCache.removeAll()
        cacheValidUntil = nil
    }

    func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)

        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            rememberInCache(value, account: account)
            return
        }

        guard status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unhandled(addStatus)
        }

        rememberInCache(value, account: account)
    }

    func read(account: String) throws -> String? {
        if let cached = cachedValue(for: account) {
            return cached
        }

        let value = try readFromKeychain(account: account)
        if let value {
            rememberInCache(value, account: account)
        }
        return value
    }

    func readProviderCredentials(for provider: ProviderAccount) throws -> ProviderKeychainCredentials? {
        guard let apiKey = try read(account: provider.keychainAccount) else {
            return nil
        }

        return ProviderKeychainCredentials(
            apiKey: apiKey,
            aliyunAccessKeyID: try read(account: provider.aliyunAccessKeyIDAccount),
            aliyunAccessKeySecret: try read(account: provider.aliyunAccessKeySecretAccount)
        )
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
        memoryCache.removeValue(forKey: account)
    }

    private func cachedValue(for account: String) -> String? {
        guard isUnlockSessionActive else {
            return nil
        }
        return memoryCache[account]
    }

    private func rememberInCache(_ value: String, account: String) {
        memoryCache[account] = value
        cacheValidUntil = Date().addingTimeInterval(unlockSessionDuration)
    }

    private func readFromKeychain(account: String) throws -> String? {
        let context = LAContext()
        context.interactionNotAllowed = true

        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.invalidData
        }

        return value
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
