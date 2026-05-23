import SwiftUI

private enum ProviderEditorTarget: Identifiable {
    case edit(UUID)
    case add

    var id: String {
        switch self {
        case .edit(let id):
            id.uuidString
        case .add:
            "add"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var editorTarget: ProviderEditorTarget?

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
                        editorTarget = .edit(provider.id)
                    })
                } else {
                    DashboardView()
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            ProviderEditorView(provider: providerForEditor(target))
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
                                editorTarget = .edit(provider.id)
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
                editorTarget = .add
            } label: {
                Label("Add Provider", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
    }

    private func providerForEditor(_ target: ProviderEditorTarget) -> ProviderAccount {
        switch target {
        case .edit(let id):
            store.providers.first(where: { $0.id == id }) ?? ProviderAccount.blank()
        case .add:
            ProviderAccount.blank()
        }
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
