import SwiftUI

struct ProviderEditorView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss

    @State private var provider: ProviderAccount
    @State private var baseURL: String
    @State private var apiKey = ""
    @State private var aliyunAccessKeyID = ""
    @State private var aliyunAccessKeySecret = ""
    @State private var openRouterManagementAPIKey = ""
    @State private var isShowingStoredAPIKey = false
    @State private var isShowingStoredAliyunAccessKeyID = false
    @State private var isShowingStoredAliyunAccessKeySecret = false
    @State private var isShowingStoredOpenRouterManagementAPIKey = false

    init(provider: ProviderAccount) {
        _provider = State(initialValue: provider)
        _baseURL = State(initialValue: provider.baseURL)
        _apiKey = State(initialValue: provider.hasStoredAPIKey ? StoredSecretPlaceholder.mask : "")
        _isShowingStoredAPIKey = State(initialValue: provider.hasStoredAPIKey)
        _aliyunAccessKeyID = State(initialValue: provider.hasStoredAliyunAccessKeys ? StoredSecretPlaceholder.mask : "")
        _aliyunAccessKeySecret = State(initialValue: provider.hasStoredAliyunAccessKeys ? StoredSecretPlaceholder.mask : "")
        _isShowingStoredAliyunAccessKeyID = State(initialValue: provider.hasStoredAliyunAccessKeys)
        _isShowingStoredAliyunAccessKeySecret = State(initialValue: provider.hasStoredAliyunAccessKeys)
        _openRouterManagementAPIKey = State(initialValue: provider.hasStoredOpenRouterManagementKey ? StoredSecretPlaceholder.mask : "")
        _isShowingStoredOpenRouterManagementAPIKey = State(initialValue: provider.hasStoredOpenRouterManagementKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(provider.id == store.selectedProviderID ? "Edit Provider" : "Provider")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Name", text: $provider.name)

                Picker("Provider", selection: $provider.kind) {
                    ForEach(ProviderKind.allCasesSortedByDisplayName) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .onChange(of: provider.kind) { _, newValue in
                    if shouldApplyDefaultBaseURL(baseURL, for: newValue) {
                        baseURL = newValue.defaultBaseURL
                    }
                }

                LabeledContent("Base URL") {
                    TextField("Base URL", text: $baseURL, prompt: Text("https://api.example.com/v1"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }

                LabeledContent(provider.kind == .openRouter ? "API Key (Vault)" : "API Key") {
                    SecureField("API Key", text: $apiKey, prompt: Text("Enter API key"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .id("\(provider.id)-api-key-\(isShowingStoredAPIKey)")
                        .help(provider.kind == .openRouter
                            ? "Store your inference API key for safekeeping. Leave the placeholder to keep the existing Keychain value."
                            : "Leave the placeholder to keep the existing Keychain value.")
                        .onChange(of: apiKey) { _, newValue in
                            if isShowingStoredAPIKey && newValue != StoredSecretPlaceholder.mask {
                                isShowingStoredAPIKey = false
                            }
                        }
                }

                if provider.kind == .openRouter {
                    Section("OpenRouter Billing") {
                        LabeledContent("Management API Key") {
                            SecureField("Management API Key", text: $openRouterManagementAPIKey, prompt: Text("Enter management API key"))
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                                .help("Leave the placeholder to keep the existing Keychain value.")
                                .onChange(of: openRouterManagementAPIKey) { _, newValue in
                                    if isShowingStoredOpenRouterManagementAPIKey && newValue != StoredSecretPlaceholder.mask {
                                        isShowingStoredOpenRouterManagementAPIKey = false
                                    }
                                }
                        }

                        if store.hasOpenRouterManagementKey(for: provider) {
                            Label("Management key saved in Keychain", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Add a management key to sync account credits. The inference API key alone can only read per-key limits and monthly usage.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if provider.kind == .aliyun {
                    Section("Aliyun Billing") {
                        LabeledContent("AccessKey ID") {
                            SecureField("AccessKey ID", text: $aliyunAccessKeyID, prompt: Text("Enter AccessKey ID"))
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                                .help("Leave the placeholder to keep the existing Keychain value.")
                                .onChange(of: aliyunAccessKeyID) { _, newValue in
                                    if isShowingStoredAliyunAccessKeyID && newValue != StoredSecretPlaceholder.mask {
                                        isShowingStoredAliyunAccessKeyID = false
                                    }
                                }
                        }
                        LabeledContent("AccessKey Secret") {
                            SecureField("AccessKey Secret", text: $aliyunAccessKeySecret, prompt: Text("Enter AccessKey Secret"))
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                                .help("Leave the placeholder to keep the existing Keychain value.")
                                .onChange(of: aliyunAccessKeySecret) { _, newValue in
                                    if isShowingStoredAliyunAccessKeySecret && newValue != StoredSecretPlaceholder.mask {
                                        isShowingStoredAliyunAccessKeySecret = false
                                    }
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
                    var savedProvider = provider
                    savedProvider.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.upsertProvider(
                        savedProvider,
                        apiKey: StoredSecretPlaceholder.valueForSave(apiKey),
                        aliyunAccessKeyID: StoredSecretPlaceholder.valueForSave(aliyunAccessKeyID),
                        aliyunAccessKeySecret: StoredSecretPlaceholder.valueForSave(aliyunAccessKeySecret),
                        openRouterManagementAPIKey: StoredSecretPlaceholder.valueForSave(openRouterManagementAPIKey)
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(provider.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .task(id: provider.id) {
            loadStoredSecretPlaceholders()
        }
    }

    private func shouldApplyDefaultBaseURL(_ current: String, for kind: ProviderKind) -> Bool {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }

        return ProviderKind.allCases
            .filter { $0 != .custom }
            .contains { $0.defaultBaseURL == trimmed }
    }

    private var storedProvider: ProviderAccount {
        store.providers.first(where: { $0.id == provider.id }) ?? provider
    }

    private func loadStoredSecretPlaceholders() {
        let current = storedProvider

        if store.hasAPIKey(for: current) {
            isShowingStoredAPIKey = true
            if apiKey.isEmpty || StoredSecretPlaceholder.isPlaceholder(apiKey) {
                apiKey = StoredSecretPlaceholder.mask
            }
        } else if isShowingStoredAPIKey {
            apiKey = ""
            isShowingStoredAPIKey = false
        }

        if store.hasAliyunAccessKeys(for: current) {
            isShowingStoredAliyunAccessKeyID = true
            isShowingStoredAliyunAccessKeySecret = true
            if aliyunAccessKeyID.isEmpty || StoredSecretPlaceholder.isPlaceholder(aliyunAccessKeyID) {
                aliyunAccessKeyID = StoredSecretPlaceholder.mask
            }
            if aliyunAccessKeySecret.isEmpty || StoredSecretPlaceholder.isPlaceholder(aliyunAccessKeySecret) {
                aliyunAccessKeySecret = StoredSecretPlaceholder.mask
            }
        } else if isShowingStoredAliyunAccessKeyID || isShowingStoredAliyunAccessKeySecret {
            aliyunAccessKeyID = ""
            aliyunAccessKeySecret = ""
            isShowingStoredAliyunAccessKeyID = false
            isShowingStoredAliyunAccessKeySecret = false
        }

        if store.hasOpenRouterManagementKey(for: current) {
            isShowingStoredOpenRouterManagementAPIKey = true
            if openRouterManagementAPIKey.isEmpty || StoredSecretPlaceholder.isPlaceholder(openRouterManagementAPIKey) {
                openRouterManagementAPIKey = StoredSecretPlaceholder.mask
            }
        } else if isShowingStoredOpenRouterManagementAPIKey {
            openRouterManagementAPIKey = ""
            isShowingStoredOpenRouterManagementAPIKey = false
        }
    }
}
