import UIKit

/// A theme made in the BetterBoard app: your own colours and, optionally, a photo.
/// Must match CustomThemeData in the app.
struct CustomThemeData: Codable, Equatable {
    /// Colours are "RRGGBBAA" hex.
    var background: String
    var key: String
    /// Outline around each key; nil = no outline.
    var border: String?
    var label: String
    var hasImage: Bool
}

/// Stores the custom theme the app sends over. With a free Apple ID the app and
/// keyboard can't share files, so the app puts the theme on the clipboard (under
/// private types) and the keyboard picks it up, saves it and clears the clipboard.
enum CustomThemeStore {
    static let themeType = "com.leisurp.betterboard.theme"
    static let imageType = "com.leisurp.betterboard.theme-image"
    private static let defaultsKey = "customTheme"
    private static let statusKey = "customThemeStatus"

    /// What happened the last time a theme arrived (shown in settings).
    static var status: String? {
        UserDefaults.standard.string(forKey: statusKey)
    }

    /// Bumped whenever a new theme arrives, so the keyboard knows to redraw.
    private(set) static var version = 0
    private static var loaded = false
    private static var cachedData: CustomThemeData?
    private static var cachedImage: UIImage?

    static var data: CustomThemeData? {
        loadIfNeeded()
        return cachedData
    }

    static var image: UIImage? {
        loadIfNeeded()
        return cachedImage
    }

    private static func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let json = UserDefaults.standard.data(forKey: defaultsKey) {
            cachedData = try? JSONDecoder().decode(CustomThemeData.self, from: json)
        }
        if cachedData?.hasImage == true, let url = imageURL {
            cachedImage = UIImage(contentsOfFile: url.path)
        }
    }

    private static var imageURL: URL? {
        guard let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("theme-background.jpg")
    }

    /// Takes a theme off the clipboard if the app put one there. Returns true if one arrived.
    static func receive(from pasteboard: UIPasteboard) -> Bool {
        guard pasteboard.contains(pasteboardTypes: [themeType]),
              let json = pasteboard.data(forPasteboardType: themeType),
              let theme = try? JSONDecoder().decode(CustomThemeData.self, from: json) else { return false }
        var note = "Colours received"
        var stored = theme
        if theme.hasImage {
            // Read the photo from the item directly too, in case the first way comes back empty.
            let imageData = pasteboard.data(forPasteboardType: imageType)
                ?? pasteboard.items.first?[imageType] as? Data
            if let imageData, UIImage(data: imageData) != nil, let url = imageURL,
               (try? imageData.write(to: url, options: .atomic)) != nil {
                note = "Photo received ✓ (\(imageData.count / 1024) KB)"
            } else {
                note = "⚠️ The photo didn't come through (\(imageData == nil ? "nothing on the clipboard" : "couldn't save it")). Tap Apply in the app again."
                stored.hasImage = false
            }
        } else if let url = imageURL {
            try? FileManager.default.removeItem(at: url)
            note = "Colours received (no photo)"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        UserDefaults.standard.set("\(note), \(formatter.string(from: Date()))", forKey: statusKey)
        UserDefaults.standard.set((try? JSONEncoder().encode(stored)) ?? json, forKey: defaultsKey)
        pasteboard.items = []
        loaded = false
        cachedData = nil
        cachedImage = nil
        version += 1
        return true
    }

    static func color(_ hex: String) -> UIColor {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        if hex.count == 6 { value = (value << 8) | 0xFF }
        return UIColor(red: CGFloat((value >> 24) & 0xFF) / 255,
                       green: CGFloat((value >> 16) & 0xFF) / 255,
                       blue: CGFloat((value >> 8) & 0xFF) / 255,
                       alpha: CGFloat(value & 0xFF) / 255)
    }

    /// Whether light text was chosen (so the keyboard counts as dark).
    static func isLight(_ color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.5
    }
}
