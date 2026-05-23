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
    var usageSnapshot: UsageSnapshot?
}

struct UsageSyncService {
    func sync(provider: ProviderAccount, apiKey: String, aliyunAccessKeyID: String? = nil, aliyunAccessKeySecret: String? = nil) async throws -> UsageSyncUpdate {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UsageSyncError.missingAPIKey
        }

        switch provider.kind {
        case .deepSeek:
            return try await syncDeepSeek(provider: provider, apiKey: apiKey)
        case .minimax:
            return try await syncMiniMax(provider: provider, apiKey: apiKey)
        case .aliyun:
            return try await syncAliyun(
                provider: provider,
                apiKey: apiKey,
                accessKeyID: aliyunAccessKeyID,
                accessKeySecret: aliyunAccessKeySecret
            )
        case .siliconFlow:
            return try await syncSiliconFlow(provider: provider, apiKey: apiKey)
        case .zhipu:
            return try await syncOpenAICompatibleModels(
                provider: provider,
                apiKey: apiKey,
                verifiedMessage: "Balance not available via public API"
            )
        case .openAI, .anthropic, .googleAI, .openRouter, .custom:
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
            supportsAutomaticSync: true,
            usageSnapshot: nil
        )
    }

    private func syncMiniMax(provider: ProviderAccount, apiKey: String) async throws -> UsageSyncUpdate {
        try await syncOpenAICompatibleModels(provider: provider, apiKey: apiKey)
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
            supportsAutomaticSync: true,
            usageSnapshot: nil
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
            supportsAutomaticSync: true,
            usageSnapshot: nil
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
                statusMessage: "API key verified; \(count) models available. Add Aliyun AK/SK to sync account bill",
                lastKnownBalance: nil,
                currencyCode: nil,
                supportsAutomaticSync: true,
                usageSnapshot: nil
            )
        }

        async let bill = queryAliyunAccountBill(
            providerID: provider.id,
            accessKeyID: accessKeyID,
            accessKeySecret: accessKeySecret
        )
        async let balance = queryAliyunAccountBalance(
            accessKeyID: accessKeyID,
            accessKeySecret: accessKeySecret
        )

        let (billSnapshot, balanceResult) = try await (bill, balance)

        return UsageSyncUpdate(
            statusMessage: "API key verified; \(count) models available. Aliyun account bill and balance synced",
            lastKnownBalance: balanceResult.amount,
            currencyCode: balanceResult.currencyCode,
            supportsAutomaticSync: true,
            usageSnapshot: billSnapshot
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

    private func queryAliyunAccountBill(providerID: UUID, accessKeyID: String, accessKeySecret: String) async throws -> UsageSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let dateComponents = calendar.dateComponents([.year, .month], from: now)
        let periodStart = calendar.date(from: dateComponents) ?? now
        let billingCycle = String(format: "%04d-%02d", dateComponents.year ?? 1970, dateComponents.month ?? 1)

        let data = try await fetchAliyunBSSResponse(
            accessKeyID: accessKeyID,
            accessKeySecret: accessKeySecret,
            action: "QueryAccountBill",
            version: "2017-12-14",
            extra: [
                "BillingCycle": billingCycle,
                "PageNum": "1",
                "PageSize": "300"
            ]
        )

        let payload: AliyunAccountBillResponse
        do {
            payload = try JSONDecoder().decode(AliyunAccountBillResponse.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw UsageSyncError.httpStatus(200, "Could not read Aliyun bill response: \(body)")
        }

        let items = payload.data.items.item
        let paidAmount = items.compactMap(\.paymentAmount?.value).reduce(0, +)
        let grossAmount = items.compactMap(\.pretaxGrossAmount?.value).reduce(0, +)
        let amount = paidAmount > 0 ? paidAmount : grossAmount

        return UsageSnapshot(
            providerID: providerID,
            periodStart: periodStart,
            periodEnd: now,
            totalCost: amount,
            requestCount: 0,
            inputTokens: 0,
            outputTokens: 0,
            currencyCode: "CNY",
            source: "Aliyun BSS QueryAccountBill",
            fetchedAt: now
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

private struct AliyunAccountBillResponse: Decodable {
    let data: AliyunAccountBillData

    enum CodingKeys: String, CodingKey {
        case data = "Data"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent(AliyunAccountBillData.self, forKey: .data) ?? AliyunAccountBillData(items: AliyunAccountBillItems(item: []))
    }
}

private struct AliyunAccountBillData: Decodable {
    let items: AliyunAccountBillItems

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }

    init(items: AliyunAccountBillItems) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent(AliyunAccountBillItems.self, forKey: .items) ?? AliyunAccountBillItems(item: [])
    }
}

private struct AliyunAccountBillItems: Decodable {
    let item: [AliyunAccountBillItem]

    enum CodingKeys: String, CodingKey {
        case item = "Item"
    }

    init(item: [AliyunAccountBillItem]) {
        self.item = item
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let item = try? container.decode([AliyunAccountBillItem].self, forKey: .item) {
            self.item = item
        } else if let item = try? container.decode(AliyunAccountBillItem.self, forKey: .item) {
            self.item = [item]
        } else {
            self.item = []
        }
    }
}

private struct AliyunAccountBillItem: Decodable {
    let paymentAmount: FlexibleDecimal?
    let pretaxGrossAmount: FlexibleDecimal?

    enum CodingKeys: String, CodingKey {
        case paymentAmount = "PaymentAmount"
        case pretaxGrossAmount = "PretaxGrossAmount"
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
