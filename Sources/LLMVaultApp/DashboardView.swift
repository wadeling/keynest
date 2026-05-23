import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        Form {
            LabeledContent("Providers") {
                Text(store.providers.count.formatted())
            }
            LabeledContent("Local storage") {
                Text("Application Support + Keychain")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Key access") {
                Text("After the first Keychain prompt, saved keys stay available for 1 hour while KeyNest is open.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Dashboard")
                    .font(.largeTitle.weight(.bold))

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 18) {
                    GridRow {
                        DashboardMetric(title: "Month Spend", value: store.totalMonthSpend.currencyString, systemImage: "dollarsign.circle")
                        DashboardMetric(
                            title: "Known Balances",
                            value: "\(store.providersWithKnownBalance)/\(store.providers.count)",
                            systemImage: "wallet.pass"
                        )
                        DashboardMetric(title: "Providers", value: store.providers.count.formatted(), systemImage: "server.rack")
                    }
                }

                ProviderBalanceList()
            }
            .padding(28)
        }
    }
}

private struct DashboardMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
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

private struct ProviderBalanceList: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Balances")
                .font(.title3.weight(.semibold))

            ForEach(store.providers) { provider in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name)
                            .font(.headline)
                        Text(provider.kind.displayName)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(store.balanceText(for: provider))
                        .font(.headline)
                        .monospacedDigit()
                }
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                )
            }
        }
    }
}
