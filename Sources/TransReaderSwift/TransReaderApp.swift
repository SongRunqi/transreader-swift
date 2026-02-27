import SwiftUI
import AppKit

@main
struct TransReaderApp: App {
    @State private var appState = AppState()
    @State private var showSettings = false
    
    var body: some Scene {
        MenuBarExtra("译", systemImage: "character.book.closed") {
            MenuBarView(appState: appState, showSettings: $showSettings)
        }
        .menuBarExtraStyle(.menu)
        
        Window("TransReader", id: "main") {
            ContentView(appState: appState, showSettings: $showSettings)
                .frame(minWidth: 480, minHeight: 400)
        }
        .defaultSize(width: 900, height: 700)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct MenuBarView: View {
    @Bindable var appState: AppState
    @Binding var showSettings: Bool
    
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        Button("截取翻译") {
            Task {
                do {
                    let text = try await appState.ocrEngine.captureScreen()
                    if !text.isEmpty {
                        appState.translate(text, source: .ocr)
                        openWindow(id: "main")
                    }
                } catch {
                    appState.error = error.localizedDescription
                }
            }
        }
        .keyboardShortcut("t", modifiers: .command)
        
        Button("显示/隐藏窗口") {
            toggleMainWindow()
        }
        .keyboardShortcut("w", modifiers: .command)
        
        Button(appState.windowPinned ? "窗口置顶: 开" : "窗口置顶") {
            togglePin()
        }
        .keyboardShortcut("p", modifiers: .command)
        
        Divider()
        
        Button("划词监控: 关") {
            // TODO: Implement selection monitor
        }
        .keyboardShortcut("m", modifiers: .command)
        .disabled(true)
        
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
        
        Button("设置") {
            showSettings = true
            openWindow(id: "main")
        }
        
        Divider()
        
        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
    
    private func toggleMainWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            openWindow(id: "main")
        }
    }
    
    private func togglePin() {
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
}
