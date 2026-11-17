import UIKit

struct ClipItem: Codable, Equatable {
    let id: UUID
    var text: String
    var date: Date
    var pinned: Bool
}

/// Remembers text you copy (Gboard-style clipboard history).
///
/// iOS only lets a keyboard look at the clipboard while it's on screen and has
/// Full Access, so items are captured when the keyboard opens and while it's open.
final class ClipboardStore {
    private(set) var items: [ClipItem] = []
    private var lastChangeCount: Int
    private let defaults = UserDefaults.standard
    private let itemsKey = "clipboardItems"
    private let changeKey = "clipboardChangeCount"
    private let maxUnpinned = 30

    /// Prefix the BetterBoard app uses to hand the Giphy key to the keyboard.
    static let giphyKeyPrefix = "BetterBoard-Giphy-Key:"

    init() {
        lastChangeCount = defaults.integer(forKey: changeKey)
        if let data = defaults.data(forKey: itemsKey),
           let saved = try? JSONDecoder().decode([ClipItem].self, from: data) {
            items = saved
        }
    }

    /// Checks the clipboard. Returns a Giphy key if the app just sent one.
    /// - Returns: (changed, giphyKey)
    func capture() -> (changed: Bool, giphyKey: String?) {
        let board = UIPasteboard.general
        guard board.changeCount != lastChangeCount else { return (false, nil) }
        lastChangeCount = board.changeCount
        defaults.set(lastChangeCount, forKey: changeKey)
        guard board.hasStrings else { return (false, nil) }
        // Password managers mark copied passwords; never store those.
        let types = board.types
        if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType") {
            return (false, nil)
        }
        guard let text = board.string else { return (false, nil) }
        if text.hasPrefix(Self.giphyKeyPrefix) {
            let key = String(text.dropFirst(Self.giphyKeyPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            board.items = []
            lastChangeCount = board.changeCount
            defaults.set(lastChangeCount, forKey: changeKey)
            return (false, key.isEmpty ? nil : key)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, text.count <= 5000 else { return (false, nil) }
        add(text)
        return (true, nil)
    }

    /// The keyboard itself changed the clipboard (e.g. copied a GIF): don't record it.
    func ignoreCurrentClipboard() {
        lastChangeCount = UIPasteboard.general.changeCount
        defaults.set(lastChangeCount, forKey: changeKey)
    }

    func add(_ text: String) {
        var pinned = false
        if let existing = items.firstIndex(where: { $0.text == text }) {
            pinned = items[existing].pinned
            items.remove(at: existing)
        }
        items.insert(ClipItem(id: UUID(), text: text, date: Date(), pinned: pinned), at: 0)
        var unpinnedSeen = 0
        items = items.filter { item in
            if item.pinned { return true }
            unpinnedSeen += 1
            return unpinnedSeen <= maxUnpinned
        }
        save()
    }

    /// Drops unpinned items older than `maxAge` (the "delete after 1 hour" setting).
    /// Returns true if anything was removed.
    @discardableResult
    func deleteOld(maxAge: TimeInterval) -> Bool {
        let cutoff = Date().addingTimeInterval(-maxAge)
        let before = items.count
        items.removeAll { !$0.pinned && $0.date < cutoff }
        guard items.count != before else { return false }
        save()
        return true
    }

    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        save()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clearUnpinned() {
        items.removeAll { !$0.pinned }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: itemsKey)
        }
    }
}
