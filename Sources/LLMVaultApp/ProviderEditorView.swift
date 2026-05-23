import SwiftUI

struct ProviderEditorView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss

    @State private var provider: ProviderAccount
    @State private var apiKey = ""
    @State private var aliyunAccessKeyID = ""
    @State private var aliyunAccessKeySecret = ""
    @State private var isShowingStoredAPIKey = false
    @State private var isShowingStoredAliyunAccessKeyID = false
    @State private var isShowingStoredAliyunAccessKeySecret = false

    init(provider: ProviderAccount) {
        _provider = State(initialValue: provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(provider.id == store.selectedProviderID ? "Edit Provider" : "Provider")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Name", text: $provider.name)

                Picker("Provider", selection: $provider.kind) {
                    ForEach(ProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .onChange(of: provider.kind) { _, newValue in
                    if provider.baseURL.isEmpty || ProviderKind.allCases.map(\.defaultBaseURL).contains(provider.baseURL) {
                        provider.baseURL = newValue.defaultBaseURL
                    }
                }

                TextField("Base URL", text: $provider.baseURL)

                TextField("Monthly Budget", value: $provider.monthlyBudget, format: .currency(code: "USD"))

                SecureField("API Key", text: $apiKey)
                    .help("Leave the placeholder to keep the existing Keychain value.")
                    .onChange(of: apiKey) { _, newValue in
                        if isShowingStoredAPIKey && newValue != StoredSecretPlaceholder.mask {
                            isShowingStoredAPIKey = false
                        }
                    }

                if provider.kind == .aliyun {
                    Section("Aliyun Billing") {
                        SecureField("AccessKey ID", text: $aliyunAccessKeyID)
                            .help("Leave the placeholder to keep the existing Keychain value.")
                            .onChange(of: aliyunAccessKeyID) { _, newValue in
                                if isShowingStoredAliyunAccessKeyID && newValue != StoredSecretPlaceholder.mask {
                                    isShowingStoredAliyunAccessKeyID = false
                                }
                            }
                        SecureField("AccessKey Secret", text: $aliyunAccessKeySecret)
                            .help("Leave the placeholder to keep the existing Keychain value.")
                            .onChange(of: aliyunAccessKeySecret) { _, newValue in
                                if isShowingStoredAliyunAccessKeySecret && newValue != StoredSecretPlaceholder.mask {
                                    isShowingStoredAliyunAccessKeySecret = false
                                }
                            }

                        if store.hasAliyunAccessKeys(for: provider) {
                            Label("Aliyun AK/SK saved in Keychain", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Add AK/SK to sync Alibaba Cloud account bills. The model API key alone can only verify the Bailian endpoint.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Toggle("Enabled", isOn: $provider.isEnabled)

                TextField("Notes", text: $provider.notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    store.upsertProvider(
                        provider,
                        apiKey: StoredSecretPlaceholder.valueForSave(apiKey),
                        aliyunAccessKeyID: StoredSecretPlaceholder.valueForSave(aliyunAccessKeyID),
                        aliyunAccessKeySecret: StoredSecretPlaceholder.valueForSave(aliyunAccessKeySecret)
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(provider.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            loadStoredSecretPlaceholders()
        }
    }

    private func loadStoredSecretPlaceholders() {
        if store.hasAPIKey(for: provider) {
            apiKey = StoredSecretPlaceholder.mask
            isShowingStoredAPIKey = true
        }

        if store.hasAliyunAccessKeys(for: provider) {
            aliyunAccessKeyID = StoredSecretPlaceholder.mask
            aliyunAccessKeySecret = StoredSecretPlaceholder.mask
            isShowingStoredAliyunAccessKeyID = true
            isShowingStoredAliyunAccessKeySecret = true
        }
    }
}
