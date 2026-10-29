import SidebarCore
import SwiftUI

@main struct SidebarApp: App {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    @NSApplicationDelegateAdaptor(SidebarAppDelegate.self) private var appDelegate
    @State private var store = WorkspaceStore()
    @State private var windowController = SidebarWindowController()
    @State private var shortcuts = ShortcutManager()

    var body: some Scene {
        Window(L10n.text("侧伴"), id: "sidebar") {
            ContentView().environment(store).environment(windowController).environment(shortcuts)
                .modifier(ShortcutLifecycle(shortcuts: shortcuts, store: store, controller: windowController))
                .environment(\.locale, AppLanguage.current().locale)
                .onAppear { windowController.connect(store: store) }
                .onChange(of: interfaceLanguage) { _, _ in
                    windowController.refreshLanguage()
                    store.notifications.refreshLanguage(tasks: store.tasks)
                }
        }
        .defaultSize(width: 420, height: NSScreen.main?.visibleFrame.height ?? 800)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra(L10n.text("侧伴"), systemImage: "square.and.pencil") {
            SidebarRecoveryMenu(controller: windowController)
                .environment(\.locale, AppLanguage.current().locale)
        }

        Settings {
            SettingsView().environment(store).environment(shortcuts)
                .environment(\.locale, AppLanguage.current().locale)
        }
    }
}

@MainActor final class SidebarAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .showSidebarRequested, object: nil)
        return true
    }
}

private struct SidebarRecoveryMenu: View {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    @Environment(\.openWindow) private var openWindow
    let controller: SidebarWindowController
    var body: some View {
        Button(L10n.text("显示侧伴")) {
            openWindow(id: "sidebar")
            controller.expand()
        }
        Divider()
        Button(L10n.text("退出侧伴")) { NSApp.terminate(nil) }
    }
}

/// Keep registration alive with the App, independent of collapsed/hidden feature views.
private struct ShortcutLifecycle: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let shortcuts: ShortcutManager
    let store: WorkspaceStore
    let controller: SidebarWindowController

    func body(content: Content) -> some View {
        content.onAppear {
            let showSidebar: () -> Void = {
                openWindow(id: "sidebar")
                controller.expand()
            }
            shortcuts.connect(actions: [
                .focus: {
                    if NSApp.isActive { NSApp.keyWindow?.makeFirstResponder(nil) }
                    store.timer.toggle()
                },
                .recording: {
                    guard !store.audio.isRequestingPermission else { return }
                    if store.audio.isRecording { store.audio.stop() }
                    else {
                        Task { @MainActor in
                            await store.audio.start()
                            if store.audio.errorMessage != nil { showSidebar() }
                        }
                    }
                },
                .sidebar: showSidebar
            ])
        }
    }
}
