import SwiftUI

// MARK: - Scholarly Color Palette (matching Python custom.css)
enum Theme {
    // MARK: - Semantic Colors
    static let background = Color("bg", bundle: nil)
    static let text = Color("text", bundle: nil)

    // Light/Dark adaptive colors using NSColor
    static var bg: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(red: 0.11, green: 0.106, blue: 0.098, alpha: 1) // #1C1B19
                : NSColor(red: 0.98, green: 0.976, blue: 0.969, alpha: 1) // #FAF9F7
        })
    }

    static var textPrimary: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(red: 0.898, green: 0.89, blue: 0.867, alpha: 1) // #E5E3DD
                : NSColor(red: 0.173, green: 0.165, blue: 0.145, alpha: 1) // #2C2A25
        })
    }

    static var textSecondary: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(red: 0.565, green: 0.553, blue: 0.522, alpha: 1) // #908D85
                : NSColor(red: 0.529, green: 0.518, blue: 0.486, alpha: 1) // #87847C
        })
    }

    static var tertiaryBg: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(red: 0.149, green: 0.145, blue: 0.133, alpha: 1) // #262522
                : NSColor(red: 0.953, green: 0.949, blue: 0.937, alpha: 1) // #F3F2EF
        })
    }

    static var accent: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(red: 0.42, green: 0.64, blue: 0.741, alpha: 1) // #6BA3BD
                : NSColor(red: 0.231, green: 0.42, blue: 0.541, alpha: 1) // #3B6B8A
        })
    }

    static var border: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(red: 0.227, green: 0.22, blue: 0.208, alpha: 1) // #3A3835
                : NSColor(red: 0.898, green: 0.89, blue: 0.867, alpha: 1) // #E5E3DD
        })
    }

    static var cardBg: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(red: 0.129, green: 0.125, blue: 0.118, alpha: 1) // #21201E
                : NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)       // #FFFFFF
        })
    }

    // MARK: - Role Colors (Grammar Chunk Roles)
    static func roleColor(_ role: String) -> Color {
        let key = normalizeRole(role)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            switch key {
            case "s", "主语":
                return isDark ? NSColor(hex: 0x7B9FCC) : NSColor(hex: 0x4A6FA5)
            case "v", "谓语":
                return isDark ? NSColor(hex: 0x82B885) : NSColor(hex: 0x5B8A5E)
            case "o", "宾语":
                return isDark ? NSColor(hex: 0xD9A876) : NSColor(hex: 0xC27D4A)
            case "a", "状语":
                return isDark ? NSColor(hex: 0xB196D0) : NSColor(hex: 0x8B6BAE)
            case "d", "定语":
                return isDark ? NSColor(hex: 0x74B5B7) : NSColor(hex: 0x4A8B8D)
            case "c", "补语":
                return isDark ? NSColor(hex: 0xD4899A) : NSColor(hex: 0xB35A6E)
            case "ap", "同位语":
                return isDark ? NSColor(hex: 0xD0B86A) : NSColor(hex: 0xA6873A)
            case "cj", "连词":
                return isDark ? NSColor(hex: 0x9A9890) : NSColor(hex: 0x7A7872)
            default:
                return isDark ? NSColor(hex: 0x9A9890) : NSColor(hex: 0x7A7872)
            }
        })
    }

    static func roleColorBg(_ role: String) -> Color {
        roleColor(role).opacity(0.12)
    }

    private static func normalizeRole(_ role: String) -> String {
        let mapping: [String: String] = [
            "主语": "s", "subject": "s",
            "谓语": "v", "predicate": "v",
            "宾语": "o", "object": "o",
            "状语": "a", "adverbial": "a",
            "定语": "d", "attributive": "d",
            "补语": "c", "complement": "c",
            "同位语": "ap", "appositive": "ap",
            "连词": "cj", "conjunction": "cj",
        ]
        return mapping[role] ?? role.lowercased()
    }

    // MARK: - Fonts
    static func serifFont(_ size: CGFloat) -> Font {
        .custom("New York", size: size, relativeTo: .body)
    }

    static let englishFont: Font = .custom("New York", size: 15, relativeTo: .body)
    @MainActor static let englishNSFont: NSFont = NSFont(name: "New York", size: 15) ?? .systemFont(ofSize: 15)
    static let chineseFont: Font = .system(size: 14)

    static let teal = Color(red: 0.29, green: 0.55, blue: 0.55) // #4A8B8D

    // MARK: - Tip Box Colors
    static var tipBg: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(red: 0.18, green: 0.22, blue: 0.18, alpha: 1)
                : NSColor(red: 0.949, green: 0.976, blue: 0.949, alpha: 1)
        })
    }

    static var tipBorder: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(hex: 0x82B885) : NSColor(hex: 0x5B8A5E)
        })
    }
}

// MARK: - NSColor Hex Helper
extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
