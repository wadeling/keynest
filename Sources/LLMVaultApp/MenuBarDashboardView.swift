import SwiftUI

struct MenuBarDashboardView: View {
    @EnvironmentObject private var store: VaultStore

    let openMainWindow: () -> Void
    let quitApplication: () -> Void
    let onPopoverEnter: () -> Void
    let onPopoverExit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("KeyNest")
                    .font(.headline)
                Spacer()
                Text("\(store.providersWithKnownBalance)/\(store.providers.count) balances")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if store.providers.isEmpty {
                Text("No providers configured")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.providers) { provider in
                        MenuBarProviderBalanceRow(provider: provider)
                    }
                }
            }

            Divider()

            HStack {
                Button("Open KeyNest") {
                    openMainWindow()
                }
                .keyboardShortcut(.defaultAction)

                Spacer()

                Button("Quit") {
                    quitApplication()
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
        .background(
            MenuBarHoverCaptureView(
                onEnter: onPopoverEnter,
                onExit: onPopoverExit
            )
        )
    }
}

private struct MenuBarProviderBalanceRow: View {
    @EnvironmentObject private var store: VaultStore
    let provider: ProviderAccount

    var body: some View {
        HStack(spacing: 10) {
            ProviderIconView(kind: provider.kind, size: 22, isEnabled: provider.isEnabled)

            VStack(alignment: .leading, spacing: 1) {
                Text(provider.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(provider.kind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(store.balanceText(for: provider))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(balanceColor)
        }
    }

    private var balanceColor: Color {
        store.syncState(for: provider.id)?.lastKnownBalance == nil ? .secondary : .primary
    }
}

private struct MenuBarHoverCaptureView: NSViewRepresentable {
    let onEnter: () -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HoverTrackingView()
        view.onEnter = onEnter
        view.onExit = onExit
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? HoverTrackingView else { return }
        view.onEnter = onEnter
        view.onExit = onExit
    }
}

private final class HoverTrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }
}
