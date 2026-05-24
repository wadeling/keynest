import Foundation
import Security

enum KeychainError: LocalizedError {
    case unhandled(OSStatus)
    case invalidData
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            "Keychain operation failed with status \(status)."
        case .invalidData:
            "The Keychain item did not contain valid text data."
        case .userCancelled:
            "Keychain access was cancelled."
        }
    }
}

struct ProviderKeychainCredentials: Sendable {
    let apiKey: String
    let aliyunAccessKeyID: String?
    let aliyunAccessKeySecret: String?
}

private struct ProviderSecrets: Codable, Hashable {
    var apiKey: String?
    var aliyunAccessKeyID: String?
    var aliyunAccessKeySecret: String?
}

private struct VaultSecrets: Codable {
    var providers: [String: ProviderSecrets] = [:]
}

@MainActor
final class KeychainService {
    static let shared = KeychainService()

    /// How long decrypted secrets stay in memory after the first load.
    var unlockSessionDuration: TimeInterval = 60 * 60

    private let service = "com.llmvault.provider-keys"
    private let vaultAccount = "keynest-vault-secrets"

    private var vaultSecrets: VaultSecrets?
    private var cacheValidUntil: Date?

    private init() {}

    var isUnlockSessionActive: Bool {
        guard let cacheValidUntil, vaultSecrets != nil else { return false }
        return Date() < cacheValidUntil
    }

    /// Loads all provider secrets with a single Keychain read.
    func loadVaultIfNeeded(providers: [ProviderAccount] = [], migrateLegacy: Bool = true) throws {
        if isUnlockSessionActive {
            return
        }

        vaultSecrets = try readVaultFromKeychain() ?? VaultSecrets()
        cacheValidUntil = Date().addingTimeInterval(unlockSessionDuration)

        if migrateLegacy, !providers.isEmpty {
            try migrateLegacyItemsIfNeeded(for: providers)
        }
    }

    func lockSession() {
        vaultSecrets = nil
        cacheValidUntil = nil
    }

    func hasAPIKey(for provider: ProviderAccount) -> Bool {
        providerSecrets(for: provider)?.apiKey != nil
    }

    func hasAliyunAccessKeys(for provider: ProviderAccount) -> Bool {
        guard let secrets = providerSecrets(for: provider) else { return false }
        return secrets.aliyunAccessKeyID != nil && secrets.aliyunAccessKeySecret != nil
    }

    func saveProviderCredentials(
        for provider: ProviderAccount,
        apiKey: String? = nil,
        aliyunAccessKeyID: String? = nil,
        aliyunAccessKeySecret: String? = nil
    ) throws {
        var vault = vaultSecrets ?? VaultSecrets()
        var secrets = vault.providers[provider.id.uuidString, default: ProviderSecrets()]

        if let apiKey {
            secrets.apiKey = apiKey
        }
        if let aliyunAccessKeyID {
            secrets.aliyunAccessKeyID = aliyunAccessKeyID
        }
        if let aliyunAccessKeySecret {
            secrets.aliyunAccessKeySecret = aliyunAccessKeySecret
        }

        vault.providers[provider.id.uuidString] = secrets
        vaultSecrets = vault
        try persistVaultToKeychain()
    }

    func readProviderCredentials(for provider: ProviderAccount) throws -> ProviderKeychainCredentials? {
        guard let secrets = providerSecrets(for: provider),
              let apiKey = secrets.apiKey
        else {
            return nil
        }

        return ProviderKeychainCredentials(
            apiKey: apiKey,
            aliyunAccessKeyID: secrets.aliyunAccessKeyID,
            aliyunAccessKeySecret: secrets.aliyunAccessKeySecret
        )
    }

    func deleteProviderCredentials(for provider: ProviderAccount) throws {
        guard var vault = vaultSecrets else { return }

        vault.providers.removeValue(forKey: provider.id.uuidString)
        vaultSecrets = vault
        try persistVaultToKeychain()
        try deleteLegacyItems(for: provider)
    }

    private func providerSecrets(for provider: ProviderAccount) -> ProviderSecrets? {
        vaultSecrets?.providers[provider.id.uuidString]
    }

    private func migrateLegacyItemsIfNeeded(for providers: [ProviderAccount]) throws {
        guard var vault = vaultSecrets else { return }

        var didChange = false

        for provider in providers {
            let providerID = provider.id.uuidString
            var secrets = vault.providers[providerID, default: ProviderSecrets()]
            var providerChanged = false

            if secrets.apiKey == nil,
               let legacyAPIKey = try readLegacyItem(account: provider.keychainAccount) {
                secrets.apiKey = legacyAPIKey
                providerChanged = true
            }

            if provider.kind == .aliyun {
                if secrets.aliyunAccessKeyID == nil,
                   let legacyAccessKeyID = try readLegacyItem(account: provider.aliyunAccessKeyIDAccount) {
                    secrets.aliyunAccessKeyID = legacyAccessKeyID
                    providerChanged = true
                }

                if secrets.aliyunAccessKeySecret == nil,
                   let legacyAccessKeySecret = try readLegacyItem(account: provider.aliyunAccessKeySecretAccount) {
                    secrets.aliyunAccessKeySecret = legacyAccessKeySecret
                    providerChanged = true
                }
            }

            if providerChanged {
                vault.providers[providerID] = secrets
                didChange = true
            }
        }

        guard didChange else { return }

        vaultSecrets = vault
        try persistVaultToKeychain()

        for provider in providers {
            try deleteLegacyItems(for: provider)
        }
    }

    private func readVaultFromKeychain() throws -> VaultSecrets? {
        guard let data = try readKeychainData(account: vaultAccount) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(VaultSecrets.self, from: data)
        } catch {
            throw KeychainError.invalidData
        }
    }

    private func persistVaultToKeychain() throws {
        guard let vaultSecrets else { return }

        let data = try JSONEncoder().encode(vaultSecrets)
        try writeKeychainData(data, account: vaultAccount)
        cacheValidUntil = Date().addingTimeInterval(unlockSessionDuration)
    }

    private func readLegacyItem(account: String) throws -> String? {
        guard let data = try readKeychainData(account: account) else {
            return nil
        }

        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return value
    }

    private func deleteLegacyItems(for provider: ProviderAccount) throws {
        for account in legacyAccounts(for: provider) {
            let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unhandled(status)
            }
        }
    }

    private func legacyAccounts(for provider: ProviderAccount) -> [String] {
        var accounts = [provider.keychainAccount]
        if provider.kind == .aliyun {
            accounts.append(provider.aliyunAccessKeyIDAccount)
            accounts.append(provider.aliyunAccessKeySecretAccount)
        }
        return accounts
    }

    private func readKeychainData(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        if status == errSecUserCanceled || status == errSecAuthFailed {
            throw KeychainError.userCancelled
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return data
    }

    private func writeKeychainData(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
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
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
