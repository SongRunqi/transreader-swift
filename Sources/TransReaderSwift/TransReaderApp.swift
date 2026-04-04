import SwiftUI
import AppKit

@main
struct TransReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @State private var showSettings = false
    @Environment(\.openWindow) private var openWindow

    private var menuBarTitle: String {
        if let stage = appState.updateStage {
            switch stage {
            case .checking:       return "译🔍"
            case .downloading:    return "译⬇️"
            case .extracting, .installing: return "译📦"
            case .relaunching:    return "译🔄"
            }
        }
        if appState.isTranslating { return "译⏳" }
        if appState.monitorEnabled { return "译👁" }
        return "译"
    }

    var body: some Scene {
        MenuBarExtra(menuBarTitle) {
            MenuBarView(appState: appState, showSettings: $showSettings)
        }
        .menuBarExtraStyle(.menu)

        Window("TransReader", id: "main") {
            ContentView(appState: appState, showSettings: $showSettings)
                .frame(minWidth: 200, minHeight: 200)
                .translationErrorAlert(appState: appState)
                .translocationAlert(appState: appState)
                .onAppear {
                    setupHotkeyCallbacks()
                    appState.setupHotkeys()
                    appState.waitForAccessibilityAndRestart()
                    appState.notificationService.requestPermission()
                    appState.handleTranslocationIfNeeded()
                    // Show window on launch (like Python)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showMainWindow()
                    }
                }
        }
        .defaultSize(width: 900, height: 700)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    private func setupHotkeyCallbacks() {
        appState.onCaptureTranslate = {
            Task { @MainActor in
                do {
                    let text = try await appState.ocrEngine.captureScreen()
                    if !text.isEmpty {
                        appState.translate(text, source: .ocr)
                        showMainWindow()
                    }
                } catch {
                    appState.error = error.localizedDescription
                }
            }
        }

        appState.onToggleWindow = {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                if window.isVisible {
                    window.orderOut(nil)
                } else {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }

        appState.onTogglePin = {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                if window.level == .floating {
                    window.level = .normal
                    appState.windowPinned = false
                } else {
                    window.level = .floating
                    appState.windowPinned = true
                }
            }
        }

        appState.onEnhanceTranslate = {
            appState.enhanceTranslate()
        }

        appState.onPasteTranslate = {
            appState.pasteTranslate()
            showMainWindow()
        }

        appState.onShowWindowNoActivate = { [openWindow] in
            openWindow(id: "main")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                    window.orderFrontRegardless()
                }
            }
        }
    }

    private func showMainWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct MenuBarView: View {
    @Bindable var appState: AppState
    @Binding var showSettings: Bool

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("截取翻译 (⌥⌘T)") {
            appState.onCaptureTranslate?()
        }

        Button("写作辅助 (⌥⌘E)") {
            appState.onEnhanceTranslate?()
        }

        Button("粘贴翻译 (⌥⌘V)") {
            appState.onPasteTranslate?()
        }

        Button("显示/隐藏窗口 (⌥⌘W)") {
            appState.onToggleWindow?()
        }

        Button(appState.windowPinned ? "窗口置顶: 开 (⌥⌘P)" : "窗口置顶 (⌥⌘P)") {
            appState.onTogglePin?()
        }

        Divider()

        Button(appState.monitorEnabled ? "划词监控: 开 (⌥⌘M)" : "划词监控: 关 (⌥⌘M)") {
            appState.toggleMonitor()
        }

        Divider()

        Menu("AI 服务商") {
            ForEach(Array(Providers.all.keys.sorted()), id: \.self) { providerID in
                Button(action: {
                    appState.configStore.setProvider(providerID)
                }) {
                    HStack {
                        Text(Providers.all[providerID]!.name)
                        if providerID == appState.configStore.provider {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        // Update menu item
        if let pending = appState.pendingUpdate {
            Button("更新到 v\(pending.version)") {
                appState.performUpdate()
            }
            .disabled(appState.updateStage != nil)
        } else {
            Button("检查更新") {
                appState.checkForUpdate()
            }
            .disabled(!Updater.isBundle || appState.updateStage != nil)
        }

        Button("设置") {
            showSettings = true
            openWindow(id: "main")
            // Bring window to front
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }

        Divider()

        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

// MARK: - App Delegate (opens main window on launch)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure main window opens on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Click Dock icon → show window
        if !flag {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}
