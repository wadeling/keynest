import AppKit
import SwiftUI

struct ProviderDetailView: View {
    @EnvironmentObject private var store: VaultStore
    let provider: ProviderAccount
    let editAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                SpendSummaryView(provider: provider)
                SyncStatusView(provider: provider)
                UsageHistoryView(provider: provider)
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top) {
            ProviderIconView(kind: provider.kind, size: 56, isEnabled: provider.isEnabled)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(provider.name)
                        .font(.largeTitle.weight(.bold))
                    if !provider.isEnabled {
                        Text("Disabled")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.secondary.opacity(0.12), in: Capsule())
                    }
                }

                Text(provider.baseURL.isEmpty ? provider.kind.displayName : provider.baseURL)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                editAction()
            } label: {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
        }
    }

}

private struct SyncStatusView: View {
    @EnvironmentObject private var store: VaultStore
    let provider: ProviderAccount
    @State private var showingUsageEntry = false
    @State private var showingAPIKey = false

    private var state: ProviderSyncState? {
        store.syncState(for: provider.id)
    }

    private var isSyncing: Bool {
        store.syncingProviderIDs.contains(provider.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(store.apiKeyPreview(for: provider), systemImage: "lock.fill")
                        .foregroundStyle(.secondary)

                    Label(state?.statusMessage ?? "Not synced yet", systemImage: statusIcon)
                        .foregroundStyle(state?.errorMessage == nil ? Color.secondary : Color.orange)

                    if let lastSyncedAt = state?.lastSyncedAt {
                        Text("Last sync: \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Auto sync: \(store.autoSyncDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let state, state.lastKnownBalance != nil {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Balance")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(state.balanceText)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                }

                Button {
                    showingAPIKey = true
                } label: {
                    Label("View Key", systemImage: "eye")
                }
                .disabled(!store.hasAPIKey(for: provider))

                Button {
                    Task {
                        await store.syncProvider(provider)
                    }
                } label: {
                    if isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(!provider.isEnabled || isSyncing)

                Button {
                    showingUsageEntry = true
                } label: {
                    Label("Add Usage", systemImage: "plus")
                }
                .disabled(!provider.isEnabled)
            }

            if let errorMessage = state?.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            } else if provider.kind == .deepSeek {
                Text("DeepSeek sync currently reads account balance. Monthly spend still comes from manual usage entries until a cost API is available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if provider.kind == .minimax {
                Text("MiniMax sync verifies the API key against the models endpoint. The public docs do not expose a billing or usage endpoint yet, so monthly spend still comes from manual usage entries.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if provider.kind == .siliconFlow {
                Text("SiliconFlow sync reads chargeBalance from the official user info endpoint. Monthly spend still comes from manual usage entries until a public billing history endpoint is added.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if provider.kind == .zhipu {
                Text("Zhipu sync only verifies the API key via the /models endpoint. Balance and usage must be checked in the Zhipu console.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if provider.kind == .aliyun {
                Text("Aliyun Bailian sync verifies the model API key, then uses Aliyun AK/SK to query account balance and the monthly account bill. If the account runs other Alibaba Cloud services, the bill can include more than Bailian model usage.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
        .sheet(isPresented: $showingUsageEntry) {
            UsageEntryView(provider: provider)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingAPIKey) {
            APIKeyViewerView(provider: provider)
                .environmentObject(store)
        }
    }

    private var statusIcon: String {
        if state?.errorMessage != nil {
            return "exclamationmark.triangle"
        }
        return state?.lastSyncedAt == nil ? "clock" : "checkmark.circle"
    }
}

private struct APIKeyViewerView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss

    let provider: ProviderAccount

    @State private var apiKey = ""
    @State private var isRevealed = false
    @State private var didCopy = false

    private var displayValue: String {
        guard !apiKey.isEmpty else { return "No API key saved" }
        if isRevealed {
            return apiKey
        }
        let visibleTail = apiKey.suffix(4)
        let maskLength = min(max(apiKey.count - 4, 12), 48)
        return String(repeating: "*", count: maskLength) + visibleTail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ProviderIconView(kind: provider.kind, size: 34, isEnabled: provider.isEnabled)
                VStack(alignment: .leading, spacing: 2) {
                    Text("API Key")
                        .font(.title2.weight(.semibold))
                    Text(provider.name)
                        .foregroundStyle(.secondary)
                }
            }

            Text(displayValue)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(4)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                )

            Text("Only reveal keys when you are ready to paste them somewhere trusted.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    isRevealed.toggle()
                } label: {
                    Label(isRevealed ? "Hide" : "Reveal", systemImage: isRevealed ? "eye.slash" : "eye")
                }
                .disabled(apiKey.isEmpty)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(apiKey, forType: .string)
                    didCopy = true
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .disabled(apiKey.isEmpty)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            apiKey = store.apiKey(for: provider) ?? ""
        }
    }
}

private struct SpendSummaryView: View {
    @EnvironmentObject private var store: VaultStore
    let provider: ProviderAccount

    private var latest: UsageSnapshot? {
        store.latestUsage(for: provider.id)
    }

    private var ratio: Double {
        guard provider.monthlyBudget > 0, let latest else { return 0 }
        let spent = NSDecimalNumber(decimal: latest.totalCost).doubleValue
        let budget = NSDecimalNumber(decimal: provider.monthlyBudget).doubleValue
        return min(spent / budget, 1)
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 18) {
            GridRow {
                MetricTile(title: "Month Spend", value: latest?.costString ?? "$0.00", systemImage: "dollarsign.circle")
                MetricTile(title: "Monthly Budget", value: provider.monthlyBudget.currencyString, systemImage: "target")
                MetricTile(title: "Requests", value: latest.map { $0.requestCount.formatted() } ?? "0", systemImage: "arrow.up.arrow.down")
            }
        }

        ProgressView(value: ratio) {
            Text("Budget usage")
        } currentValueLabel: {
            Text("\(Int(ratio * 100))%")
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))

            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

private struct UsageHistoryView: View {
    @EnvironmentObject private var store: VaultStore
    let provider: ProviderAccount

    private var snapshots: [UsageSnapshot] {
        store.usage
            .filter { $0.providerID == provider.id }
            .sorted { $0.fetchedAt > $1.fetchedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Usage History")
                .font(.title3.weight(.semibold))

            if snapshots.isEmpty {
                ContentUnavailableView("No usage data", systemImage: "chart.line.uptrend.xyaxis")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                Table(snapshots) {
                    TableColumn("Fetched") { snapshot in
                        Text(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    TableColumn("Cost") { snapshot in
                        Text(snapshot.costString)
                            .monospacedDigit()
                    }
                    TableColumn("Requests") { snapshot in
                        Text(snapshot.requestCount.formatted())
                            .monospacedDigit()
                    }
                    TableColumn("Input") { snapshot in
                        Text(snapshot.inputTokens.formatted())
                            .monospacedDigit()
                    }
                    TableColumn("Output") { snapshot in
                        Text(snapshot.outputTokens.formatted())
                            .monospacedDigit()
                    }
                    TableColumn("Source") { snapshot in
                        Text(snapshot.source)
                    }
                }
                .frame(minHeight: 260)
            }
        }
    }
}

private struct UsageEntryView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss

    let provider: ProviderAccount

    @State private var totalCost: Decimal = 0
    @State private var requestCount = 0
    @State private var inputTokens = 0
    @State private var outputTokens = 0
    @State private var source = "Manual entry"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Usage")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Cost", value: $totalCost, format: .currency(code: "USD"))
                TextField("Requests", value: $requestCount, format: .number)
                TextField("Input Tokens", value: $inputTokens, format: .number)
                TextField("Output Tokens", value: $outputTokens, format: .number)
                TextField("Source", text: $source)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func save() {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let snapshot = UsageSnapshot(
            providerID: provider.id,
            periodStart: start,
            periodEnd: Date(),
            totalCost: totalCost,
            requestCount: requestCount,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            currencyCode: "USD",
            source: source.isEmpty ? "Manual entry" : source,
            fetchedAt: Date()
        )

        store.addUsageSnapshot(snapshot)
        dismiss()
    }
}
