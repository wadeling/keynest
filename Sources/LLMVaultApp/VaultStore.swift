import Foundation
import SwiftUI

@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var providers: [ProviderAccount] = []
    @Published private(set) var syncStates: [ProviderSyncState] = []
    @Published private(set) var balanceHistory: [BalanceSnapshot] = []
    @Published private(set) var syncingProviderIDs: Set<UUID> = []
    @Published var sidebarSelection: SidebarSelection = .dashboard
    @Published var alertMessage: String?

    var selectedProviderID: UUID? {
        guard case .provider(let id) = sidebarSelection else { return nil }
        return id
    }

    private let keychain = KeychainService.shared
    private let syncService = UsageSyncService()
    private let fileManager = FileManager.default
    private let autoSyncInterval: UInt64 = 6 * 60 * 60

    private var providersURL: URL {
        appSupportURL.appending(path: "providers.json")
    }

    private var syncURL: URL {
        appSupportURL.appending(path: "sync.json")
    }

    private var balanceHistoryURL: URL {
        appSupportURL.appending(path: "balance-history.json")
    }

    private var appSupportURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "LLMVault", directoryHint: .isDirectory)
    }

    init() {
        load()
    }

    var selectedProvider: ProviderAccount? {
        guard case .provider(let id) = sidebarSelection else { return nil }
        return providers.first { $0.id == id }
    }

    var providersWithKnownBalance: Int {
        providers.filter { syncState(for: $0.id)?.lastKnownBalance != nil }.count
    }

    var autoSyncDescription: String {
        "Every 6 hours while the app is open; first run after 6 hours"
    }

    func hasAPIKey(for provider: ProviderAccount) -> Bool {
        provider.hasStoredAPIKey
    }

    func syncState(for providerID: UUID) -> ProviderSyncState? {
        syncStates.first { $0.providerID == providerID }
    }

    func balanceText(for provider: ProviderAccount) -> String {
        guard let state = syncState(for: provider.id),
              state.lastKnownBalance != nil
        else {
            return "—"
        }
        return state.balanceText
    }

    func balanceHistory(for providerID: UUID) -> [BalanceSnapshot] {
        balanceHistory
            .filter { $0.providerID == providerID }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    func apiKeyPreview(for provider: ProviderAccount) -> String {
        guard hasAPIKey(for: provider) else { return "No key saved" }
        return "Saved in Keychain"
    }

    func hasAliyunAccessKeys(for provider: ProviderAccount) -> Bool {
        provider.hasStoredAliyunAccessKeys
    }

    func apiKey(for provider: ProviderAccount) -> String? {
        do {
            try ensureKeyAccess()
            return try keychain.readProviderCredentials(for: provider)?.apiKey
        } catch {
            alertMessage = error.localizedDescription
            return nil
        }
    }

    func upsertProvider(
        _ provider: ProviderAccount,
        apiKey: String?,
        aliyunAccessKeyID: String? = nil,
        aliyunAccessKeySecret: String? = nil
    ) {
        var updated = provider
        updated.updatedAt = Date()

        let resolvedAPIKey = resolvedProviderAPIKey(apiKey: apiKey)
        let resolvedAliyunAccessKeyID = resolvedProviderAPIKey(apiKey: aliyunAccessKeyID)
        let resolvedAliyunAccessKeySecret = resolvedProviderAPIKey(apiKey: aliyunAccessKeySecret)

        do {
            try keychain.loadVaultIfNeeded(providers: providers)

            if resolvedAPIKey != nil || resolvedAliyunAccessKeyID != nil || resolvedAliyunAccessKeySecret != nil {
                try keychain.saveProviderCredentials(
                    for: updated,
                    apiKey: resolvedAPIKey,
                    aliyunAccessKeyID: resolvedAliyunAccessKeyID,
                    aliyunAccessKeySecret: resolvedAliyunAccessKeySecret
                )
            }

            if resolvedAPIKey != nil {
                updated.hasStoredAPIKey = true
            }

            if updated.kind == .aliyun {
                updated.hasStoredAliyunAccessKeys = keychain.hasAliyunAccessKeys(for: updated)
            }
        } catch {
            alertMessage = error.localizedDescription
            return
        }

        if let index = providers.firstIndex(where: { $0.id == updated.id }) {
            providers[index] = updated
        } else {
            providers.append(updated)
            sidebarSelection = .provider(updated.id)
        }

        save()
    }

    func deleteProvider(_ provider: ProviderAccount) {
        do {
            try keychain.loadVaultIfNeeded(providers: providers)
            try keychain.deleteProviderCredentials(for: provider)
        } catch {
            alertMessage = error.localizedDescription
        }

        providers.removeAll { $0.id == provider.id }
        syncStates.removeAll { $0.providerID == provider.id }
        balanceHistory.removeAll { $0.providerID == provider.id }
        if case .provider(let id) = sidebarSelection, id == provider.id {
            sidebarSelection = providers.first.map { .provider($0.id) } ?? .dashboard
        }
        save()
    }

    func syncProvider(_ provider: ProviderAccount) async {
        guard !syncingProviderIDs.contains(provider.id) else { return }

        syncingProviderIDs.insert(provider.id)
        defer { syncingProviderIDs.remove(provider.id) }

        do {
            try ensureKeyAccess()

            guard let credentials = try keychain.readProviderCredentials(for: provider) else {
                throw UsageSyncError.missingAPIKey
            }

            let update = try await syncService.sync(
                provider: provider,
                apiKey: credentials.apiKey,
                aliyunAccessKeyID: credentials.aliyunAccessKeyID,
                aliyunAccessKeySecret: credentials.aliyunAccessKeySecret
            )
            upsertSyncState(ProviderSyncState(
                providerID: provider.id,
                lastSyncedAt: Date(),
                statusMessage: update.statusMessage,
                errorMessage: nil,
                lastKnownBalance: update.lastKnownBalance,
                currencyCode: update.currencyCode,
                supportsAutomaticSync: update.supportsAutomaticSync
            ))
            if let balance = update.lastKnownBalance, let currencyCode = update.currencyCode {
                recordBalanceSnapshot(
                    providerID: provider.id,
                    balance: balance,
                    currencyCode: currencyCode,
                    recordedAt: Date()
                )
            }
        } catch {
            upsertSyncState(ProviderSyncState(
                providerID: provider.id,
                lastSyncedAt: syncState(for: provider.id)?.lastSyncedAt,
                statusMessage: "Sync unavailable",
                errorMessage: error.localizedDescription,
                lastKnownBalance: syncState(for: provider.id)?.lastKnownBalance,
                currencyCode: syncState(for: provider.id)?.currencyCode,
                supportsAutomaticSync: provider.kind == .deepSeek || provider.kind == .minimax || provider.kind == .aliyun || provider.kind == .siliconFlow || provider.kind == .zhipu || provider.kind == .liaobots
            ))
        }
    }

    func syncAllProviders() async {
        do {
            try ensureKeyAccess()
        } catch {
            alertMessage = error.localizedDescription
            return
        }

        for provider in providers where provider.isEnabled {
            await syncProvider(provider)
        }
    }

    func startAutoSyncLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(autoSyncInterval))
            await syncAllProviders()
        }
    }

    private func load() {
        do {
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: providersURL.path) {
                let data = try Data(contentsOf: providersURL)
                providers = try JSONDecoder.vault.decode([ProviderAccount].self, from: data)
            }

            if fileManager.fileExists(atPath: syncURL.path) {
                let data = try Data(contentsOf: syncURL)
                syncStates = try JSONDecoder.vault.decode([ProviderSyncState].self, from: data)
            }

            if fileManager.fileExists(atPath: balanceHistoryURL.path) {
                let data = try Data(contentsOf: balanceHistoryURL)
                balanceHistory = try JSONDecoder.vault.decode([BalanceSnapshot].self, from: data)
            }

            migrateStoredKeyFlagsIfNeeded()
            migrateBalanceHistoryIfNeeded()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func migrateStoredKeyFlagsIfNeeded() {
        // Key presence is resolved lazily when credentials are loaded from the vault.
    }

    private func migrateBalanceHistoryIfNeeded() {
        var changed = false

        for state in syncStates {
            guard let balance = state.lastKnownBalance,
                  let currencyCode = state.currencyCode,
                  let recordedAt = state.lastSyncedAt,
                  !balanceHistory.contains(where: { $0.providerID == state.providerID })
            else {
                continue
            }

            balanceHistory.append(BalanceSnapshot(
                providerID: state.providerID,
                balance: balance,
                currencyCode: currencyCode,
                recordedAt: recordedAt
            ))
            changed = true
        }

        if changed {
            save()
        }
    }

    private func ensureKeyAccess() throws {
        try keychain.loadVaultIfNeeded(providers: providers)
    }

    private func resolvedProviderAPIKey(apiKey: String?) -> String? {
        guard let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

            let providerData = try JSONEncoder.vault.encode(providers)
            try providerData.write(to: providersURL, options: [.atomic])

            let syncData = try JSONEncoder.vault.encode(syncStates)
            try syncData.write(to: syncURL, options: [.atomic])

            let balanceHistoryData = try JSONEncoder.vault.encode(balanceHistory)
            try balanceHistoryData.write(to: balanceHistoryURL, options: [.atomic])
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func upsertSyncState(_ state: ProviderSyncState) {
        if let index = syncStates.firstIndex(where: { $0.providerID == state.providerID }) {
            syncStates[index] = state
        } else {
            syncStates.append(state)
        }
        save()
    }

    private func recordBalanceSnapshot(
        providerID: UUID,
        balance: Decimal,
        currencyCode: String,
        recordedAt: Date
    ) {
        balanceHistory.append(BalanceSnapshot(
            providerID: providerID,
            balance: balance,
            currencyCode: currencyCode,
            recordedAt: recordedAt
        ))
        save()
    }
}

private extension JSONEncoder {
    static var vault: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var vault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
