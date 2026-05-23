import Foundation
import SwiftUI

@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var providers: [ProviderAccount] = []
    @Published private(set) var usage: [UsageSnapshot] = []
    @Published private(set) var syncStates: [ProviderSyncState] = []
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

    private var usageURL: URL {
        appSupportURL.appending(path: "usage.json")
    }

    private var syncURL: URL {
        appSupportURL.appending(path: "sync.json")
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

    var totalMonthSpend: Decimal {
        currentMonthUsage.reduce(0) { $0 + $1.totalCost }
    }

    var totalMonthlyBudget: Decimal {
        providers.reduce(0) { $0 + $1.monthlyBudget }
    }

    var providersWithKnownBalance: Int {
        providers.filter { syncState(for: $0.id)?.lastKnownBalance != nil }.count
    }

    var currentMonthUsage: [UsageSnapshot] {
        let calendar = Calendar.current
        return usage.filter { calendar.isDate($0.periodStart, equalTo: Date(), toGranularity: .month) }
    }

    var autoSyncDescription: String {
        "Every 6 hours while the app is open; first run after 6 hours"
    }

    func latestUsage(for providerID: UUID) -> UsageSnapshot? {
        usage
            .filter { $0.providerID == providerID }
            .sorted { $0.fetchedAt > $1.fetchedAt }
            .first
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

    func apiKeyPreview(for provider: ProviderAccount) -> String {
        guard hasAPIKey(for: provider) else { return "No key saved" }
        return "Saved in Keychain"
    }

    func hasAliyunAccessKeys(for provider: ProviderAccount) -> Bool {
        provider.hasStoredAliyunAccessKeys
    }

    func apiKey(for provider: ProviderAccount) -> String? {
        do {
            keychain.beginUnlockSession()
            return try keychain.read(account: provider.keychainAccount)
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

        if let resolvedAPIKey {
            do {
                try keychain.save(resolvedAPIKey, account: updated.keychainAccount)
                updated.hasStoredAPIKey = true
            } catch {
                alertMessage = error.localizedDescription
                return
            }
        }

        if let aliyunAccessKeyID, !aliyunAccessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try keychain.save(aliyunAccessKeyID, account: updated.aliyunAccessKeyIDAccount)
            } catch {
                alertMessage = error.localizedDescription
                return
            }
        }

        if let aliyunAccessKeySecret, !aliyunAccessKeySecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try keychain.save(aliyunAccessKeySecret, account: updated.aliyunAccessKeySecretAccount)
            } catch {
                alertMessage = error.localizedDescription
                return
            }
        }

        if updated.kind == .aliyun {
            updated.hasStoredAliyunAccessKeys = provider.hasStoredAliyunAccessKeys
                || ((try? keychain.read(account: updated.aliyunAccessKeyIDAccount)) != nil
                    && (try? keychain.read(account: updated.aliyunAccessKeySecretAccount)) != nil)
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
            try keychain.delete(account: provider.keychainAccount)
            try keychain.delete(account: provider.aliyunAccessKeyIDAccount)
            try keychain.delete(account: provider.aliyunAccessKeySecretAccount)
        } catch {
            alertMessage = error.localizedDescription
        }

        providers.removeAll { $0.id == provider.id }
        usage.removeAll { $0.providerID == provider.id }
        syncStates.removeAll { $0.providerID == provider.id }
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
            keychain.beginUnlockSession()

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
            if let usageSnapshot = update.usageSnapshot {
                upsertSyncedUsageSnapshot(usageSnapshot)
            }
        } catch {
            upsertSyncState(ProviderSyncState(
                providerID: provider.id,
                lastSyncedAt: syncState(for: provider.id)?.lastSyncedAt,
                statusMessage: "Sync unavailable",
                errorMessage: error.localizedDescription,
                lastKnownBalance: syncState(for: provider.id)?.lastKnownBalance,
                currencyCode: syncState(for: provider.id)?.currencyCode,
                supportsAutomaticSync: provider.kind == .deepSeek || provider.kind == .minimax || provider.kind == .aliyun || provider.kind == .siliconFlow || provider.kind == .zhipu
            ))
        }
    }

    func syncAllProviders() async {
        keychain.beginUnlockSession()
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

    func addUsageSnapshot(_ snapshot: UsageSnapshot) {
        usage.append(snapshot)
        save()
    }

    func upsertSyncedUsageSnapshot(_ snapshot: UsageSnapshot) {
        if let index = usage.firstIndex(where: {
            $0.providerID == snapshot.providerID
                && $0.source == snapshot.source
                && Calendar.current.isDate($0.periodStart, equalTo: snapshot.periodStart, toGranularity: .month)
        }) {
            usage[index] = snapshot
        } else {
            usage.append(snapshot)
        }
        save()
    }

    func addUsageSample(for provider: ProviderAccount) {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let snapshot = UsageSnapshot(
            providerID: provider.id,
            periodStart: start,
            periodEnd: Date(),
            totalCost: Decimal(Double.random(in: 1.2...18.5)),
            requestCount: Int.random(in: 120...2800),
            inputTokens: Int.random(in: 50_000...2_000_000),
            outputTokens: Int.random(in: 20_000...850_000),
            currencyCode: "USD",
            source: "Local sample",
            fetchedAt: Date()
        )
        addUsageSnapshot(snapshot)
    }

    func removeUsage(_ snapshot: UsageSnapshot) {
        usage.removeAll { $0.id == snapshot.id }
        save()
    }

    private func load() {
        do {
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: providersURL.path) {
                let data = try Data(contentsOf: providersURL)
                providers = try JSONDecoder.vault.decode([ProviderAccount].self, from: data)
            }

            if fileManager.fileExists(atPath: usageURL.path) {
                let data = try Data(contentsOf: usageURL)
                usage = try JSONDecoder.vault.decode([UsageSnapshot].self, from: data)
            }

            if fileManager.fileExists(atPath: syncURL.path) {
                let data = try Data(contentsOf: syncURL)
                syncStates = try JSONDecoder.vault.decode([ProviderSyncState].self, from: data)
            }

            migrateStoredKeyFlagsIfNeeded()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func migrateStoredKeyFlagsIfNeeded() {
        let needsMigration = providers.contains {
            !$0.hasStoredAPIKey || ($0.kind == .aliyun && !$0.hasStoredAliyunAccessKeys)
        }
        guard needsMigration else { return }

        var changed = false
        for index in providers.indices {
            if !providers[index].hasStoredAPIKey,
               (try? keychain.read(account: providers[index].keychainAccount)) != nil {
                providers[index].hasStoredAPIKey = true
                changed = true
            }

            if providers[index].kind == .aliyun,
               !providers[index].hasStoredAliyunAccessKeys,
               (try? keychain.read(account: providers[index].aliyunAccessKeyIDAccount)) != nil,
               (try? keychain.read(account: providers[index].aliyunAccessKeySecretAccount)) != nil {
                providers[index].hasStoredAliyunAccessKeys = true
                changed = true
            }
        }

        if changed {
            save()
        }
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

            let usageData = try JSONEncoder.vault.encode(usage)
            try usageData.write(to: usageURL, options: [.atomic])

            let syncData = try JSONEncoder.vault.encode(syncStates)
            try syncData.write(to: syncURL, options: [.atomic])
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
