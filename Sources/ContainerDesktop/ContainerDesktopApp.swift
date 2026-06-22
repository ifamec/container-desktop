import AppKit
import SwiftUI

@main
struct ContainerDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .frame(minWidth: 980, minHeight: 640)
                .task { store.start() }
                .onChange(of: scenePhase) { _, phase in store.appIsActive = phase == .active }
                .alert("Container Desktop", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                    Button("OK") { store.errorMessage = nil }
                } message: { Text(store.errorMessage ?? "") }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
            StandardEditCommands()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let packagedIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        let developmentIcon = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Assets/container-desktop-app-icon-v3.png")
        if let iconURL = packagedIcon ?? (FileManager.default.fileExists(atPath: developmentIcon.path) ? developmentIcon : nil),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.forEach {
                $0.toolbar = nil
                $0.titleVisibility = .hidden
                $0.titlebarAppearsTransparent = true
                $0.styleMask.insert(.fullSizeContentView)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct StandardEditCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { send(#selector(NSText.cut(_:))) }
                .keyboardShortcut("x", modifiers: .command)
            Button("Copy") { send(#selector(NSText.copy(_:))) }
                .keyboardShortcut("c", modifiers: .command)
            Button("Paste") { send(#selector(NSText.paste(_:))) }
                .keyboardShortcut("v", modifiers: .command)
            Divider()
            Button("Select All") { send(#selector(NSResponder.selectAll(_:))) }
                .keyboardShortcut("a", modifiers: .command)
        }
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}
