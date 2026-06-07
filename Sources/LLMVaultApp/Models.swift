import Foundation

enum ProviderKind: String, CaseIterable, Codable, Identifiable {
    case openAI
    case anthropic
    case googleAI
    case openRouter
    case deepSeek
    case aliyun
    case minimax
    case siliconFlow
    case zhipu
    case liaobots
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .googleAI: "Google AI"
        case .openRouter: "OpenRouter"
        case .deepSeek: "DeepSeek"
        case .aliyun: "Aliyun Bailian"
        case .minimax: "MiniMax"
        case .siliconFlow: "SiliconFlow"
        case .zhipu: "Zhipu AI"
        case .liaobots: "LiaoBots"
        case .custom: "Custom"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .googleAI: "https://generativelanguage.googleapis.com/v1beta"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .deepSeek: "https://api.deepseek.com"
        case .aliyun: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .minimax: "https://api.minimaxi.com/v1"
        case .siliconFlow: "https://api.siliconflow.cn/v1"
        case .zhipu: "https://open.bigmodel.cn/api/paas/v4"
        case .liaobots: "https://ai.liaobots.work/api/v1"
        case .custom: ""
        }
    }

    static var allCasesSortedByDisplayName: [ProviderKind] {
        allCases.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

enum SidebarSelection: Hashable, Sendable {
    case dashboard
    case provider(UUID)
}

struct ProviderAccount: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var kind: ProviderKind
    var baseURL: String
    var monthlyBudget: Decimal
    var notes: String
    var isEnabled: Bool
    var hasStoredAPIKey: Bool = false
    var hasStoredAliyunAccessKeys: Bool = false
    var hasStoredOpenRouterManagementKey: Bool = false
    var createdAt: Date
    var updatedAt: Date

    var keychainAccount: String {
        "provider-key-\(id.uuidString)"
    }

    var aliyunAccessKeyIDAccount: String {
        "aliyun-access-key-id-\(id.uuidString)"
    }

    var aliyunAccessKeySecretAccount: String {
        "aliyun-access-key-secret-\(id.uuidString)"
    }

    static func blank(kind: ProviderKind = .openAI) -> ProviderAccount {
        ProviderAccount(
            name: kind.displayName,
            kind: kind,
            baseURL: kind.defaultBaseURL,
            monthlyBudget: 50,
            notes: "",
            isEnabled: true,
            hasStoredAPIKey: false,
            hasStoredAliyunAccessKeys: false,
            hasStoredOpenRouterManagementKey: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: ProviderKind,
        baseURL: String,
        monthlyBudget: Decimal,
        notes: String,
        isEnabled: Bool,
        hasStoredAPIKey: Bool = false,
        hasStoredAliyunAccessKeys: Bool = false,
        hasStoredOpenRouterManagementKey: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.monthlyBudget = monthlyBudget
        self.notes = notes
        self.isEnabled = isEnabled
        self.hasStoredAPIKey = hasStoredAPIKey
        self.hasStoredAliyunAccessKeys = hasStoredAliyunAccessKeys
        self.hasStoredOpenRouterManagementKey = hasStoredOpenRouterManagementKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(ProviderKind.self, forKey: .kind)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        monthlyBudget = try container.decode(Decimal.self, forKey: .monthlyBudget)
        notes = try container.decode(String.self, forKey: .notes)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        hasStoredAPIKey = try container.decodeIfPresent(Bool.self, forKey: .hasStoredAPIKey) ?? false
        hasStoredAliyunAccessKeys = try container.decodeIfPresent(Bool.self, forKey: .hasStoredAliyunAccessKeys) ?? false
        hasStoredOpenRouterManagementKey = try container.decodeIfPresent(Bool.self, forKey: .hasStoredOpenRouterManagementKey) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct ProviderSyncState: Identifiable, Codable, Hashable, Sendable {
    var providerID: UUID
    var lastSyncedAt: Date?
    var statusMessage: String
    var errorMessage: String?
    var lastKnownBalance: Decimal?
    var currencyCode: String?
    var supportsAutomaticSync: Bool

    var id: UUID { providerID }

    var balanceText: String {
        guard let lastKnownBalance, let currencyCode else { return "Unknown" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: lastKnownBalance)) ?? "\(currencyCode) \(lastKnownBalance)"
    }
}

struct BalanceSnapshot: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var providerID: UUID
    var balance: Decimal
    var currencyCode: String
    var recordedAt: Date

    var balanceValue: Double {
        NSDecimalNumber(decimal: balance).doubleValue
    }
}

extension Decimal {
    var currencyString: String {
        currencyString(code: "USD")
    }

    func currencyString(code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: self)) ?? "$0.00"
    }
}
