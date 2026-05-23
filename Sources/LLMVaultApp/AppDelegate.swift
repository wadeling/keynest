import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var menuBarController: MenuBarController?
    private var didStartBackgroundServices = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func configure(store: VaultStore, openMainWindow: @escaping () -> Void) {
        menuBarController?.configure(store: store, openMainWindow: openMainWindow)

        guard !didStartBackgroundServices else { return }
        didStartBackgroundServices = true

        Task {
            await store.startAutoSyncLoop()
        }
    }
}
