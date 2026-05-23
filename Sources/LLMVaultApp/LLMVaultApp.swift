import SwiftUI

@main
struct LLMVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = VaultStore()

    var body: some Scene {
        WindowGroup("KeyNest", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1080, minHeight: 680)
                .background(AppBootstrapView(store: store, appDelegate: appDelegate))
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

private struct AppBootstrapView: NSViewRepresentable {
    let store: VaultStore
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.bootstrapIfNeeded()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.store = store
        context.coordinator.appDelegate = appDelegate
        context.coordinator.openWindow = openWindow
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var store: VaultStore?
        var appDelegate: AppDelegate?
        var openWindow: OpenWindowAction?
        private var didBootstrap = false

        @MainActor
        func bootstrapIfNeeded() {
            guard !didBootstrap,
                  let store,
                  let appDelegate
            else {
                return
            }

            didBootstrap = true
            appDelegate.configure(store: store) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    self.openWindow?(id: "main")
                }
            }
        }
    }
}
