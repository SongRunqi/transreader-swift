import Foundation
import AppKit
import Carbon

enum HotkeyAction: String {
    case captureTranslate = "capture_translate"
    case toggleWindow = "toggle_window"
    case togglePin = "toggle_pin"
    case toggleMonitor = "toggle_monitor"
    case quit = "quit"
}

actor GlobalHotkeys {
    private var monitors: [Any] = []
    private var shortcuts: [String: String] = [:]
    private let callbacks: [HotkeyAction: () -> Void]
    
    init(shortcuts: [String: String], callbacks: [HotkeyAction: () -> Void]) {
        self.shortcuts = shortcuts
        self.callbacks = callbacks
    }
    
    func register() {
        unregister()
        
        for (actionKey, shortcut) in shortcuts {
            guard let action = HotkeyAction(rawValue: actionKey),
                  let callback = callbacks[action],
                  let (modifiers, keyCode) = parseShortcut(shortcut) else {
                continue
            }
            
            // Create global event monitor
            let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == keyCode,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers else {
                    return
                }
                
                callback()
            }
            
            if let monitor = monitor {
                monitors.append(monitor)
            }
            
            // Also add local monitor (for when app is active)
            let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == keyCode,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers else {
                    return event
                }
                
                callback()
                return nil  // Event consumed
            }
            
            if let localMonitor = localMonitor {
                monitors.append(localMonitor)
            }
        }
    }
    
    func unregister() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
    }
    
    func updateShortcuts(_ shortcuts: [String: String]) {
        self.shortcuts = shortcuts
        register()
    }
    
    private func parseShortcut(_ shortcut: String) -> (NSEvent.ModifierFlags, UInt16)? {
        // Expected format: "cmd+t", "cmd+shift+w", etc.
        let parts = shortcut.lowercased().components(separatedBy: "+")
        guard parts.count >= 2 else { return nil }
        
        var modifiers: NSEvent.ModifierFlags = []
        var keyChar = ""
        
        for part in parts {
            switch part {
            case "cmd", "command":
                modifiers.insert(.command)
            case "shift":
                modifiers.insert(.shift)
            case "option", "opt", "alt":
                modifiers.insert(.option)
            case "ctrl", "control":
                modifiers.insert(.control)
            default:
                keyChar = part
            }
        }
        
        guard !keyChar.isEmpty,
              let keyCode = keyCodeForChar(keyChar) else {
            return nil
        }
        
        return (modifiers, keyCode)
    }
    
    private func keyCodeForChar(_ char: String) -> UInt16? {
        // Common key codes (US QWERTY layout)
        let keyMap: [String: UInt16] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04,
            "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
            "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F,
            "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
            "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C,
            "9": 0x19, "0": 0x1D, "o": 0x1F, "u": 0x20, "i": 0x22,
            "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D,
            "m": 0x2E, "-": 0x1B, "=": 0x18, "[": 0x21, "]": 0x1E,
            ";": 0x29, "'": 0x27, ",": 0x2B, ".": 0x2F, "/": 0x2C,
            "`": 0x32, "\\": 0x2A,
            "return": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33,
            "escape": 0x35, "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
            "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64, "f9": 0x65,
            "f10": 0x6D, "f11": 0x67, "f12": 0x6F
        ]
        
        return keyMap[char.lowercased()]
    }
}
