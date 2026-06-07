import Foundation
import CryptoKit

enum UsageSyncError: LocalizedError {
    case missingAPIKey
    case unsupportedProvider(String)
    case invalidURL
    case httpStatus(Int, String)
    case noBalance

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No API key is saved for this provider."
        case .unsupportedProvider(let provider):
            "\(provider) does not have an automatic usage sync adapter yet."
        case .invalidURL:
            "The provider base URL is invalid."
        case .httpStatus(let status, let body):
            "Sync failed with HTTP \(status): \(body)"
        case .noBalance:
            "The provider did not return a usable balance."
        }
    }
}

struct UsageSyncUpdate: Sendable {
    var statusMessage: String
    var lastKnownBalance: Decimal?
    var currencyCode: String?
    var supportsAutomaticSync: Bool
}

struct UsageSyncService {
    func sync(
        provider: ProviderAccount,
        apiKey: String,
        aliyunAccessKeyID: String? = nil,
        aliyunAccessKeySecret: String? = nil,
        openRouterManagementAPIKey: String? = nil
    ) async throws -> UsageSyncUpdate {
        switch provider.kind {
        case .openRouter:
            let hasAPIKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasManagementKey = !(openRouterManagementAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            guard hasAPIKey || hasManagementKey else {
                throw UsageSyncError.missingAPIKey
            }
            return try await syncOpenRouter(
                provider: provider,
                apiKey: apiKey,
                managementAPIKey: openRouterManagementAPIKey
            )
        case .deepSeek:
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw UsageSyncError.missingAPIKey
            }
            return try await syncDeepSeek(provider: provider, apiKey: apiKey)
        case .minimax:
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw UsageSyncError.missingAPIKey
            }
            return try await syncMiniMax(provider: provider, apiKey: apiKey)
        case .aliyun:
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw UsageSyncError.missingAPIKey
            }
            return try await syncAliyun(
                provider: provider,
                apiKey: apiKey,
                accessKeyID: aliyunAccessKeyID,
                accessKeySecret: aliyunAccessKeySecret
            )
        case .siliconFlow:
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw UsageSyncError.missingAPIKey
            }
            return try await syncSiliconFlow(provider: provider, apiKey: apiKey)
        case .zhipu:
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw UsageSyncError.missingAPIKey
            }
            return try await syncOpenAICompatibleModels(
                provider: provider,
                apiKey: apiKey,
                verifiedMessage: "Balance not available via public API"
            )
        case .liaobots:
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw UsageSyncError.missingAPIKey
            }
            return try await syncLiaobots(provider: provider, apiKey: apiKey)
        case .openAI, .anthropic, .googleAI, .custom:
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw UsageSyncError.missingAPIKey
            }
            throw UsageSyncError.unsupportedProvider(provider.kind.displayName)
        }
    }

    private func syncDeepSeek(provider: ProviderAccount, apiKey: String) async throws -> UsageSyncUpdate {
        let base = provider.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/user/balance") else {
            throw UsageSyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageSyncError.httpStatus(-1, "Invalid response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw UsageSyncError.httpStatus(http.statusCode, body)
        }

        let payload = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        guard let balance = payload.balanceInfos.first,
              let amount = Decimal(string: balance.totalBalance)
        else {
            throw UsageSyncError.noBalance
        }

        return UsageSyncUpdate(
            statusMessage: payload.isAvailable ? "Balance synced" : "Balance synced, but account is not available",
            lastKnownBalance: amount,
            currencyCode: balance.currency,
            supportsAutomaticSync: true
        )
    }

    private func syncMiniMax(provider: ProviderAccount, apiKey: String) async throws -> UsageSyncUpdate {
        var lastError: Error?

        for baseURL in miniMaxCandidateBaseURLs(for: provider) {
            do {
                return try await verifyMiniMaxAPIKey(baseURL: baseURL, apiKey: apiKey)
            } catch UsageSyncError.httpStatus(401, let body) {
                lastError = UsageSyncError.httpStatus(401, body)
            } catch {
                throw error
            }
        }

        if let lastError {
            throw lastError
        }

        throw UsageSyncError.httpStatus(401, "Invalid API key")
    }

    private func miniMaxCandidateBaseURLs(for provider: ProviderAccount) -> [String] {
        let trimmed = provider.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var bases: [String]

        if trimmed.isEmpty {
            bases = [
                ProviderKind.minimax.defaultBaseURL,
                "https://api.minimax.io/v1"
            ]
        } else {
            bases = [trimmed]
            if trimmed.contains("api.minimax.io") {
                bases.append(trimmed.replacingOccurrences(of: "api.minimax.io", with: "api.minimaxi.com"))
            } else if trimmed.contains("api.minimaxi.com") {
                bases.append(trimmed.replacingOccurrences(of: "api.minimaxi.com", with: "api.minimax.io"))
            }
        }

        return Array(Set(bases))
    }

    private func verifyMiniMaxAPIKey(baseURL: String, apiKey: String) async throws -> UsageSyncUpdate {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw UsageSyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(MiniMaxVerificationRequest())

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageSyncError.httpStatus(-1, "Invalid response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw UsageSyncError.httpStatus(http.statusCode, body)
        }

        if let payload = try? JSONDecoder().decode(MiniMaxChatCompletionResponse.self, from: data),
           let baseResp = payload.baseResp,
           baseResp.statusCode != 0 {
            throw UsageSyncError.httpStatus(
                http.statusCode,
                baseResp.statusMsg ?? "MiniMax API error \(baseResp.statusCode)"
            )
        }

        return UsageSyncUpdate(
            statusMessage: "API key verified via chat/completions. Check balance in the MiniMax console.",
            lastKnownBalance: nil,
            currencyCode: nil,
            supportsAutomaticSync: true
        )
    }

    private func syncOpenAICompatibleModels(provider: ProviderAccount, apiKey: String, verifiedMessage: String = "Billing sync unavailable") async throws -> UsageSyncUpdate {
        let base = provider.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/models") else {
            throw UsageSyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageSyncError.httpStatus(-1, "Invalid response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw UsageSyncError.httpStatus(http.statusCode, body)
        }

        let payload = try JSONDecoder().decode(ModelsResponse.self, from: data)
        let count = payload.data.count

        return UsageSyncUpdate(
            statusMessage: "API key verified; \(count) models available. \(verifiedMessage)",
            lastKnownBalance: nil,
            currencyCode: nil,
            supportsAutomaticSync: true
        )
    }

    private func syncSiliconFlow(provider: ProviderAccount, apiKey: String) async throws -> UsageSyncUpdate {
        let base = provider.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/user/info") else {
            throw UsageSyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageSyncError.httpStatus(-1, "Invalid response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw UsageSyncError.httpStatus(http.statusCode, body)
        }

        let userInfo: SiliconFlowUserInfoData
        do {
            userInfo = try JSONDecoder().decode(SiliconFlowUserInfoResponse.self, from: data).data
        } catch {
            guard let fallback = parseSiliconFlowUserInfoFallback(from: data) else {
                let body = String(data: data, encoding: .utf8) ?? "No response body"
                throw UsageSyncError.httpStatus(
                    http.statusCode,
                    "Could not read SiliconFlow user info response: \(body) (\(error.localizedDescription))"
                )
            }
            userInfo = fallback
        }

        guard let balance = userInfo.chargeBalance?.value ?? userInfo.balance?.value ?? userInfo.totalBalance?.value else {
            throw UsageSyncError.noBalance
        }

        let statusSuffix = userInfo.status.map { " (\($0))" } ?? ""
        return UsageSyncUpdate(
            statusMessage: "Charge balance synced\(statusSuffix)",
            lastKnownBalance: balance,
            currencyCode: "CNY",
            supportsAutomaticSync: true
        )
    }

    private func syncOpenRouter(
        provider: ProviderAccount,
        apiKey: String,
        managementAPIKey: String?
    ) async throws -> UsageSyncUpdate {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedManagementKey = managementAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var balance: Decimal?
        var statusMessage = "OpenRouter synced"

        if !trimmedManagementKey.isEmpty {
            let credits = try await fetchOpenRouterAccountCredits(apiKey: trimmedManagementKey)
            balance = credits.data.totalCredits.value - credits.data.totalUsage.value
            statusMessage = "Account credits synced"
        }

        if !trimmedAPIKey.isEmpty {
            let keyInfo = try await fetchOpenRouterKeyInfo(apiKey: trimmedAPIKey)
            let keyData = keyInfo.data

            if balance == nil, let remaining = keyData.limitRemaining?.value {
                balance = remaining
                statusMessage = "Key credit limit synced"
            }

            let monthlyUsage = keyData.usageMonthly.value
            if monthlyUsage > 0 {
                statusMessage += "; $\(monthlyUsage) used this month"
            }

            if let label = keyData.label, !label.isEmpty {
                statusMessage += " (\(label))"
            }
        }

        return UsageSyncUpdate(
            statusMessage: statusMessage,
            lastKnownBalance: balance,
            currencyCode: balance == nil ? nil : "USD",
            supportsAutomaticSync: true
        )
    }

    private func fetchOpenRouterKeyInfo(apiKey: String) async throws -> OpenRouterKeyResponse {
        guard let url = URL(string: "https://openrouter.ai/api/v1/key") else {
            throw UsageSyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageSyncError.httpStatus(-1, "Invalid response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw UsageSyncError.httpStatus(http.statusCode, body)
        }

        return try JSONDecoder().decode(OpenRouterKeyResponse.self, from: data)
    }

    private func fetchOpenRouterAccountCredits(apiKey: String) async throws -> OpenRouterCreditsResponse {
        guard let url = URL(string: "https://openrouter.ai/api/v1/credits") else {
            throw UsageSyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageSyncError.httpStatus(-1, "Invalid response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw UsageSyncError.httpStatus(http.statusCode, body)
        }

        return try JSONDecoder().decode(OpenRouterCreditsResponse.self, from: data)
    }

    private func syncLiaobots(provider: ProviderAccount, apiKey: String) async throws -> UsageSyncUpdate {
        let base = provider.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/credits") else {
            throw UsageSyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageSyncError.httpStatus(-1, "Invalid response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw UsageSyncError.httpStatus(http.statusCode, body)
        }

        let payload = try JSONDecoder().decode(LiaobotsCreditsResponse.self, from: data)
        guard let balance = payload.data.balance?.value else {
            throw UsageSyncError.noBalance
        }

        let statusMessage: String
        if let total = payload.data.amount?.value {
            statusMessage = "Credits synced (\(balance) remaining of \(total))"
        } else {
            statusMessage = "Credits synced"
        }

        return UsageSyncUpdate(
            statusMessage: statusMessage,
            lastKnownBalance: balance,
            currencyCode: "PTS",
            supportsAutomaticSync: true
        )
    }

    private func syncAliyun(provider: ProviderAccount, apiKey: String, accessKeyID: String?, accessKeySecret: String?) async throws -> UsageSyncUpdate {
        let base = provider.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/models") else {
            throw UsageSyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageSyncError.httpStatus(-1, "Invalid response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw UsageSyncError.httpStatus(http.statusCode, body)
        }

        let payload = try JSONDecoder().decode(ModelsResponse.self, from: data)
        let count = payload.data.count

        guard let accessKeyID, let accessKeySecret,
              !accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !accessKeySecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return UsageSyncUpdate(
                statusMessage: "API key verified; \(count) models available. Add Aliyun AK/SK to sync account balance",
                lastKnownBalance: nil,
                currencyCode: nil,
                supportsAutomaticSync: true
            )
        }

        let balanceResult = try await queryAliyunAccountBalance(
            accessKeyID: accessKeyID,
            accessKeySecret: accessKeySecret
        )

        return UsageSyncUpdate(
            statusMessage: "API key verified; \(count) models available. Aliyun account balance synced",
            lastKnownBalance: balanceResult.amount,
            currencyCode: balanceResult.currencyCode,
            supportsAutomaticSync: true
        )
    }

    private struct AliyunAccountBalanceResult {
        let amount: Decimal
        let currencyCode: String
    }

    private func queryAliyunAccountBalance(accessKeyID: String, accessKeySecret: String) async throws -> AliyunAccountBalanceResult {
        let data = try await fetchAliyunBSSResponse(
            accessKeyID: accessKeyID,
            accessKeySecret: accessKeySecret,
            action: "QueryAccountBalance",
            version: "2017-12-14"
        )

        let payload: AliyunAccountBalanceResponse
        do {
            payload = try JSONDecoder().decode(AliyunAccountBalanceResponse.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw UsageSyncError.httpStatus(200, "Could not read Aliyun balance response: \(body)")
        }

        let balanceData = payload.data
        guard let amount = balanceData.availableCashAmount?.value ?? balanceData.availableAmount?.value else {
            throw UsageSyncError.noBalance
        }

        return AliyunAccountBalanceResult(
            amount: amount,
            currencyCode: balanceData.currency ?? "CNY"
        )
    }

    private func fetchAliyunBSSResponse(
        accessKeyID: String,
        accessKeySecret: String,
        action: String,
        version: String,
        extra: [String: String] = [:]
    ) async throws -> Data {
        let parameters = signedAliyunParameters(
            action: action,
            version: version,
            accessKeyID: accessKeyID,
            accessKeySecret: accessKeySecret,
            extra: extra
        )

        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = "business.aliyuncs.com"
        urlComponents.path = "/"
        urlComponents.percentEncodedQuery = canonicalQuery(parameters)

        guard let url = urlComponents.url else {
            throw UsageSyncError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw UsageSyncError.httpStatus(-1, "Invalid response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw UsageSyncError.httpStatus(http.statusCode, body)
        }

        return data
    }

    private func signedAliyunParameters(action: String, version: String, accessKeyID: String, accessKeySecret: String, extra: [String: String]) -> [String: String] {
        var parameters = extra
        parameters["Action"] = action
        parameters["Version"] = version
        parameters["Format"] = "JSON"
        parameters["AccessKeyId"] = accessKeyID
        parameters["SignatureMethod"] = "HMAC-SHA1"
        parameters["Timestamp"] = iso8601Timestamp()
        parameters["SignatureVersion"] = "1.0"
        parameters["SignatureNonce"] = UUID().uuidString

        let canonical = canonicalQuery(parameters)
        let stringToSign = "GET&%2F&\(percentEncode(canonical))"
        let key = SymmetricKey(data: Data("\(accessKeySecret)&".utf8))
        let signature = HMAC<Insecure.SHA1>.authenticationCode(for: Data(stringToSign.utf8), using: key)
        parameters["Signature"] = Data(signature).base64EncodedString()

        return parameters
    }

    private func canonicalQuery(_ parameters: [String: String]) -> String {
        parameters
            .sorted { $0.key < $1.key }
            .map { "\(percentEncode($0.key))=\(percentEncode($0.value))" }
            .joined(separator: "&")
    }

    private func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func iso8601Timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    private func parseSiliconFlowUserInfoFallback(from data: Data) -> SiliconFlowUserInfoData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let userInfo = (json["data"] as? [String: Any]) ?? json
        let balance = decimalValue(from: userInfo["balance"]).map { FlexibleDecimal(value: $0) }
        let chargeBalance = decimalValue(from: userInfo["chargeBalance"]).map { FlexibleDecimal(value: $0) }
        let totalBalance = decimalValue(from: userInfo["totalBalance"]).map { FlexibleDecimal(value: $0) }
        let status = stringValue(from: userInfo["status"])

        guard balance != nil || chargeBalance != nil || totalBalance != nil else {
            return nil
        }

        return SiliconFlowUserInfoData(
            balance: balance,
            chargeBalance: chargeBalance,
            totalBalance: totalBalance,
            status: status
        )
    }

    private func decimalValue(from value: Any?) -> Decimal? {
        switch value {
        case let string as String:
            return Decimal(string: string, locale: posixDecimalLocale)
        case let number as NSNumber:
            return Decimal(string: number.stringValue, locale: posixDecimalLocale)
        case let double as Double:
            return Decimal(double)
        case let int as Int:
            return Decimal(int)
        default:
            return nil
        }
    }

    private func stringValue(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "active" : "inactive"
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }
}

private let posixDecimalLocale = Locale(identifier: "en_US_POSIX")

private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [DeepSeekBalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

private struct DeepSeekBalanceInfo: Decodable {
    let currency: String
    let totalBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
    }
}

private struct ModelsResponse: Decodable {
    let data: [ProviderModel]
}

private struct ProviderModel: Decodable {
    let id: String
}

private struct MiniMaxVerificationRequest: Encodable {
    let model = "MiniMax-M2.7"
    let messages = [MiniMaxVerificationMessage(role: "user", content: "ping")]
    let maxCompletionTokens = 1

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxCompletionTokens = "max_completion_tokens"
    }
}

private struct MiniMaxVerificationMessage: Encodable {
    let role: String
    let content: String
}

private struct MiniMaxChatCompletionResponse: Decodable {
    let baseResp: MiniMaxBaseResponse?

    enum CodingKeys: String, CodingKey {
        case baseResp = "base_resp"
    }
}

private struct MiniMaxBaseResponse: Decodable {
    let statusCode: Int
    let statusMsg: String?

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMsg = "status_msg"
    }
}

private struct OpenRouterKeyResponse: Decodable {
    let data: OpenRouterKeyData
}

private struct OpenRouterKeyData: Decodable {
    let label: String?
    let limitRemaining: FlexibleDecimal?
    let usageMonthly: FlexibleDecimal

    enum CodingKeys: String, CodingKey {
        case label
        case limitRemaining = "limit_remaining"
        case usageMonthly = "usage_monthly"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        limitRemaining = try container.decodeIfPresent(FlexibleDecimal.self, forKey: .limitRemaining)
        usageMonthly = try container.decodeIfPresent(FlexibleDecimal.self, forKey: .usageMonthly) ?? FlexibleDecimal(value: 0)
    }
}

private struct OpenRouterCreditsResponse: Decodable {
    let data: OpenRouterCreditsData
}

private struct OpenRouterCreditsData: Decodable {
    let totalCredits: FlexibleDecimal
    let totalUsage: FlexibleDecimal

    enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }
}

private struct LiaobotsCreditsResponse: Decodable {
    let data: LiaobotsCreditsData
}

private struct LiaobotsCreditsData: Decodable {
    let balance: FlexibleDecimal?
    let amount: FlexibleDecimal?
}

private struct SiliconFlowUserInfoResponse: Decodable {
    let data: SiliconFlowUserInfoData
}

private struct SiliconFlowUserInfoData: Decodable {
    let balance: FlexibleDecimal?
    let chargeBalance: FlexibleDecimal?
    let totalBalance: FlexibleDecimal?
    let status: String?

    init(
        balance: FlexibleDecimal? = nil,
        chargeBalance: FlexibleDecimal? = nil,
        totalBalance: FlexibleDecimal? = nil,
        status: String? = nil
    ) {
        self.balance = balance
        self.chargeBalance = chargeBalance
        self.totalBalance = totalBalance
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        balance = try container.decodeIfPresent(FlexibleDecimal.self, forKey: .balance)
        chargeBalance = try container.decodeIfPresent(FlexibleDecimal.self, forKey: .chargeBalance)
        totalBalance = try container.decodeIfPresent(FlexibleDecimal.self, forKey: .totalBalance)

        if let statusString = try? container.decode(String.self, forKey: .status) {
            status = statusString
        } else if let statusBool = try? container.decode(Bool.self, forKey: .status) {
            status = statusBool ? "active" : "inactive"
        } else {
            status = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case balance
        case chargeBalance
        case totalBalance
        case status
    }
}

private struct AliyunAccountBalanceResponse: Decodable {
    let data: AliyunAccountBalanceData

    enum CodingKeys: String, CodingKey {
        case data = "Data"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent(AliyunAccountBalanceData.self, forKey: .data) ?? AliyunAccountBalanceData()
    }
}

private struct AliyunAccountBalanceData: Decodable {
    let availableAmount: FlexibleDecimal?
    let availableCashAmount: FlexibleDecimal?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case availableAmount = "AvailableAmount"
        case availableCashAmount = "AvailableCashAmount"
        case currency = "Currency"
    }

    init(
        availableAmount: FlexibleDecimal? = nil,
        availableCashAmount: FlexibleDecimal? = nil,
        currency: String? = nil
    ) {
        self.availableAmount = availableAmount
        self.availableCashAmount = availableCashAmount
        self.currency = currency
    }
}

private struct FlexibleDecimal: Decodable {
    let value: Decimal

    init(value: Decimal) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let decimal = try? container.decode(Decimal.self) {
            value = decimal
            return
        }

        if let double = try? container.decode(Double.self) {
            value = Decimal(double)
            return
        }

        if let int = try? container.decode(Int.self) {
            value = Decimal(int)
            return
        }

        if let string = try? container.decode(String.self),
           let decimal = Decimal(string: string, locale: posixDecimalLocale) {
            value = decimal
            return
        }

        value = 0
    }
}
