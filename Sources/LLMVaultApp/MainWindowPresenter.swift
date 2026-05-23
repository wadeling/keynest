import AppKit
import SwiftUI

@MainActor
enum MainWindowPresenter {
    private static var openWindow: OpenWindowAction?
    private static weak var mainWindow: NSWindow?

    static func register(_ action: OpenWindowAction) {
        openWindow = action
    }

    static func attachMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.delegate = MainWindowDelegate.shared
    }

    static func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }

        openWindow?(id: "main")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let window = NSApp.windows.first(where: isMainWindow) {
                attachMainWindow(window)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private static func isMainWindow(_ window: NSWindow) -> Bool {
        window.title == "KeyNest"
            || window.identifier?.rawValue.contains("main") == true
    }
}

@MainActor
final class MainWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = MainWindowDelegate()

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

enum StoredSecretPlaceholder {
    static let mask = String(repeating: "*", count: 12)

    static func isPlaceholder(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return trimmed.allSatisfy { $0 == "*" || $0 == "•" }
    }

    static func valueForSave(_ value: String) -> String? {
        isPlaceholder(value) ? nil : value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MainWindowAccessor: NSViewRepresentable {
    @Environment(\.openWindow) private var openWindow

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            MainWindowPresenter.register(openWindow)
            if let window = view.window {
                MainWindowPresenter.attachMainWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        MainWindowPresenter.register(openWindow)
        if let window = nsView.window {
            MainWindowPresenter.attachMainWindow(window)
        }
    }
}

extension View {
    func attachMainWindowPresenter() -> some View {
        background(MainWindowAccessor())
    }
}
