import AppKit
import SwiftUI

private final class StatusItemMouseTracker: NSObject {
    weak var controller: MenuBarController?

    @objc func mouseEntered(with event: NSEvent) {
        DispatchQueue.main.async { [weak controller] in
            controller?.handleStatusItemMouseEntered()
        }
    }

    @objc func mouseExited(with event: NSEvent) {
        DispatchQueue.main.async { [weak controller] in
            controller?.handleStatusItemMouseExited()
        }
    }
}

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var hostingController: NSHostingController<AnyView>?
    private var store: VaultStore?
    private var openMainWindow: (() -> Void)?
    private var hideTimer: Timer?
    private var isPointerInsidePopover = false
    private let mouseTracker = StatusItemMouseTracker()

    override init() {
        super.init()
        mouseTracker.controller = self
    }

    func configure(store: VaultStore, openMainWindow: @escaping () -> Void) {
        self.store = store
        self.openMainWindow = { MainWindowPresenter.show() }

        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        if let button = item.button {
            if let image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "KeyNest") {
                image.isTemplate = true
                button.image = image
            }
            button.toolTip = "KeyNest"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            let trackingArea = NSTrackingArea(
                rect: button.bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: mouseTracker,
                userInfo: nil
            )
            button.addTrackingArea(trackingArea)
        }

        popover.behavior = .applicationDefined
        popover.animates = true
        installPopoverContentIfNeeded()
    }

    func handleStatusItemMouseEntered() {
        cancelHideTimer()
        showPopover()
    }

    func handleStatusItemMouseExited() {
        scheduleHidePopover()
    }

    func popoverMouseEntered() {
        isPointerInsidePopover = true
        cancelHideTimer()
    }

    func popoverMouseExited() {
        isPointerInsidePopover = false
        scheduleHidePopover()
    }

    private func makeDashboardView() -> AnyView {
        AnyView(
            MenuBarDashboardView(
                openMainWindow: { [weak self] in
                    self?.hidePopover()
                    self?.openMainWindow?()
                },
                quitApplication: {
                    NSApplication.shared.terminate(nil)
                },
                onPopoverEnter: { [weak self] in
                    self?.popoverMouseEntered()
                },
                onPopoverExit: { [weak self] in
                    self?.popoverMouseExited()
                }
            )
            .environmentObject(store!)
        )
    }

    private func installPopoverContentIfNeeded() {
        guard hostingController == nil, store != nil else { return }

        let controller = NSHostingController(rootView: makeDashboardView())
        hostingController = controller
        popover.contentViewController = controller
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
            return
        }

        if popover.isShown {
            hidePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        cancelHideTimer()
        guard let button = statusItem?.button, !popover.isShown else { return }

        installPopoverContentIfNeeded()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func hidePopover() {
        cancelHideTimer()
        popover.performClose(nil)
    }

    private func scheduleHidePopover() {
        cancelHideTimer()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPointerInsidePopover else { return }
                self.hidePopover()
            }
        }
    }

    private func cancelHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open KeyNest", action: #selector(openMainWindowAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit KeyNest", action: #selector(quitApplicationAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openMainWindowAction() {
        hidePopover()
        openMainWindow?()
    }

    @objc private func quitApplicationAction() {
        NSApplication.shared.terminate(nil)
    }
}
