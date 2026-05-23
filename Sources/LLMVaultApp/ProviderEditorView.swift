import SwiftUI

struct ProviderEditorView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss

    @State private var provider: ProviderAccount
    @State private var apiKey = ""
    @State private var aliyunAccessKeyID = ""
    @State private var aliyunAccessKeySecret = ""

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
                    .help("Leave empty to keep the existing Keychain value.")

                if provider.kind == .aliyun {
                    Section("Aliyun Billing") {
                        SecureField("AccessKey ID", text: $aliyunAccessKeyID)
                            .help("Used only for Alibaba Cloud BSS billing queries. Leave empty to keep the existing Keychain value.")
                        SecureField("AccessKey Secret", text: $aliyunAccessKeySecret)
                            .help("Used only for Alibaba Cloud BSS billing queries. Leave empty to keep the existing Keychain value.")

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
                        apiKey: apiKey,
                        aliyunAccessKeyID: aliyunAccessKeyID,
                        aliyunAccessKeySecret: aliyunAccessKeySecret
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(provider.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
