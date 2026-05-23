import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var showingEditor = false
    @State private var editingProvider: ProviderAccount?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch store.sidebarSelection {
            case .dashboard:
                DashboardView()
            case .provider(let id):
                if let provider = store.providers.first(where: { $0.id == id }) {
                    ProviderDetailView(provider: provider, editAction: {
                        editingProvider = provider
                        showingEditor = true
                    })
                } else {
                    DashboardView()
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ProviderEditorView(provider: editingProvider ?? ProviderAccount.blank())
                .environmentObject(store)
        }
        .alert("KeyNest", isPresented: Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.alertMessage = nil } }
        )) {
            Button("OK") {
                store.alertMessage = nil
            }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }

    private var sidebar: some View {
        List(selection: $store.sidebarSelection) {
            Section {
                DashboardRow()
                    .tag(SidebarSelection.dashboard)
            }

            Section("Providers") {
                ForEach(store.providers) { provider in
                    ProviderRow(provider: provider)
                        .tag(SidebarSelection.provider(provider.id))
                        .contextMenu {
                            Button("Edit") {
                                editingProvider = provider
                                showingEditor = true
                            }
                            Button("Delete", role: .destructive) {
                                store.deleteProvider(provider)
                            }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                editingProvider = ProviderAccount.blank()
                showingEditor = true
            } label: {
                Label("Add Provider", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
    }
}

private struct DashboardRow: View {
    var body: some View {
        Label("Dashboard", systemImage: "chart.bar.xaxis")
            .font(.headline)
    }
}

private struct ProviderRow: View {
    @EnvironmentObject private var store: VaultStore
    let provider: ProviderAccount

    var body: some View {
        HStack(spacing: 10) {
            ProviderIconView(kind: provider.kind, size: 30, isEnabled: provider.isEnabled)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .lineLimit(1)
                Text(provider.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.hasAPIKey(for: provider) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}
