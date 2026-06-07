import AppKit
import Charts
import SwiftUI

struct ProviderDetailView: View {
    @EnvironmentObject private var store: VaultStore
    let provider: ProviderAccount
    let editAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                SyncStatusView(provider: provider)
                BalanceHistoryView(provider: provider)
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
            }

            if let errorMessage = state?.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            } else if provider.kind == .deepSeek {
                Text("DeepSeek sync reads account balance from the official API.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if provider.kind == .minimax {
                Text("MiniMax sync verifies the API key via chat/completions. China keys use api.minimaxi.com; international keys use api.minimax.io.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if provider.kind == .siliconFlow {
                Text("SiliconFlow sync reads charge balance from the official user info endpoint.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if provider.kind == .zhipu {
                Text("Zhipu sync verifies the API key. Check balance in the Zhipu console.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if provider.kind == .liaobots {
                Text("LiaoBots sync reads credit balance from GET /credits using your auth code.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if provider.kind == .openRouter {
                Text("OpenRouter sync uses the management key for account credits (GET /api/v1/credits) and the inference API key for per-key limits and monthly usage (GET /api/v1/key).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if provider.kind == .aliyun {
                Text("Aliyun sync verifies the Bailian API key and queries account balance via AK/SK.")
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

private struct BalanceHistoryView: View {
    @EnvironmentObject private var store: VaultStore
    let provider: ProviderAccount

    @State private var highlightedSnapshot: BalanceSnapshot?

    private var snapshots: [BalanceSnapshot] {
        store.balanceHistory(for: provider.id)
    }

    private var currencyCode: String {
        snapshots.last?.currencyCode
            ?? store.syncState(for: provider.id)?.currencyCode
            ?? "USD"
    }

    private var yAxisDomain: ClosedRange<Double> {
        let values = snapshots.map(\.balanceValue)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }
        let span = max(maxValue - minValue, maxValue * 0.1, 1)
        let lower = max(0, minValue - span * 0.15)
        let upper = maxValue + span * 0.2
        return lower...upper
    }

    private var usesExplicitXAxis: Bool {
        snapshots.count <= 6
    }

    private var showsTimeOnXAxis: Bool {
        guard snapshots.count > 1,
              let first = snapshots.first?.recordedAt,
              let last = snapshots.last?.recordedAt
        else {
            return false
        }
        return last.timeIntervalSince(first) <= 86_400 * 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("余额历史曲线")
                .font(.title3.weight(.semibold))

            if snapshots.isEmpty {
                ContentUnavailableView("暂无余额历史", systemImage: "chart.line.uptrend.xyaxis")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                Chart(snapshots) { snapshot in
                    LineMark(
                        x: .value("时间", snapshot.recordedAt),
                        y: .value("余额", snapshot.balanceValue)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor)

                    PointMark(
                        x: .value("时间", snapshot.recordedAt),
                        y: .value("余额", snapshot.balanceValue)
                    )
                    .symbolSize(isHighlighted(snapshot) ? 90 : 44)
                    .foregroundStyle(isHighlighted(snapshot) ? Color.accentColor : Color.accentColor.opacity(highlightedSnapshot == nil ? 1 : 0.35))

                    if highlightedSnapshot?.id == snapshot.id {
                        RuleMark(x: .value("时间", snapshot.recordedAt))
                            .foregroundStyle(Color.accentColor.opacity(0.25))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartYScale(domain: yAxisDomain)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    if usesExplicitXAxis {
                        AxisMarks(values: snapshots.map(\.recordedAt)) { value in
                            AxisGridLine()
                            AxisTick()
                            if let date = value.as(Date.self) {
                                AxisValueLabel(formatXAxisLabel(date))
                            }
                        }
                    } else {
                        AxisMarks(values: .automatic(desiredCount: 5)) { value in
                            AxisGridLine()
                            AxisTick()
                            if let date = value.as(Date.self) {
                                AxisValueLabel(formatXAxisLabel(date))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        highlightedSnapshot = nearestSnapshot(
                                            at: location,
                                            proxy: proxy,
                                            geometry: geometry
                                        )
                                    case .ended:
                                        highlightedSnapshot = nil
                                    }
                                }

                            if let highlightedSnapshot,
                               let plotFrame = plotFrame(in: geometry, proxy: proxy),
                               let xPosition = proxy.position(forX: highlightedSnapshot.recordedAt),
                               let yPosition = proxy.position(forY: highlightedSnapshot.balanceValue) {
                                BalanceChartTooltip(snapshot: highlightedSnapshot)
                                    .position(
                                        x: plotFrame.origin.x + xPosition,
                                        y: plotFrame.origin.y + yPosition - 32
                                    )
                            }
                        }
                    }
                }
                .frame(minHeight: 220)
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                )

                HStack {
                    Text("共 \(snapshots.count) 次同步记录 · \(currencyCode)")
                    Spacer()
                    Text("悬停圆点查看数值")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func isHighlighted(_ snapshot: BalanceSnapshot) -> Bool {
        highlightedSnapshot?.id == snapshot.id
    }

    private func formatXAxisLabel(_ date: Date) -> String {
        if showsTimeOnXAxis {
            date.formatted(date: .abbreviated, time: .shortened)
        } else {
            date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private func plotFrame(in geometry: GeometryProxy, proxy: ChartProxy) -> CGRect? {
        guard let anchor = proxy.plotFrame else { return nil }
        return geometry[anchor]
    }

    private func nearestSnapshot(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) -> BalanceSnapshot? {
        guard let plotFrame = plotFrame(in: geometry, proxy: proxy),
              plotFrame.contains(location)
        else {
            return nil
        }

        let x = location.x - plotFrame.origin.x
        let maxDistance: CGFloat = 24

        return snapshots.min { lhs, rhs in
            let lhsDistance = proxy.position(forX: lhs.recordedAt).map { abs($0 - x) } ?? .infinity
            let rhsDistance = proxy.position(forX: rhs.recordedAt).map { abs($0 - x) } ?? .infinity
            return lhsDistance < rhsDistance
        }.flatMap { candidate in
            guard let pointX = proxy.position(forX: candidate.recordedAt),
                  abs(pointX - x) <= maxDistance
            else {
                return nil
            }
            return candidate
        }
    }
}

private struct BalanceChartTooltip: View {
    let snapshot: BalanceSnapshot

    var body: some View {
        VStack(spacing: 2) {
            Text(snapshot.balance.currencyString(code: snapshot.currencyCode))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            Text(snapshot.recordedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.quaternary, lineWidth: 0.5)
        )
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
