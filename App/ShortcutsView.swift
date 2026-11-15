import SwiftUI

/// Must match ShortcutEntry in the keyboard (the id isn't sent).
struct ShortcutEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var shortcut: String
    var phrase: String
}

/// Your email, phone and address, plus shortcuts like "addr" → your address.
/// The keyboard suggests them as you start typing them (like Gboard).
struct ShortcutsView: View {
    @AppStorage("personalEmail") private var email = ""
    @AppStorage("personalEmail2") private var email2 = ""
    @AppStorage("personalPhone") private var phone = ""
    @AppStorage("personalAddress") private var address = ""
    @AppStorage("shortcutsJSON") private var shortcutsJSON = "[]"
    @State private var shortcuts: [ShortcutEntry] = []
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Second email (optional)", text: $email2)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                TextField("Address", text: $address, axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                Text("Your info")
            } footer: {
                Text("Start typing any of these and the whole thing shows up in the suggestion bar. In email boxes, your emails show up straight away.")
            }

            Section {
                ForEach($shortcuts) { $entry in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Shortcut, e.g. addr", text: $entry.shortcut)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.headline)
                        TextField("Phrase it types", text: $entry.phrase, axis: .vertical)
                            .lineLimit(1...4)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { shortcuts.remove(atOffsets: $0) }
                Button {
                    shortcuts.append(ShortcutEntry(shortcut: "", phrase: ""))
                } label: {
                    Label("Add shortcut", systemImage: "plus")
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Type the shortcut and the full phrase appears in the suggestion bar. Tap it to use it. Swipe left to delete one.")
            }

            Section {
                Button("Send to keyboard") { send() }
                    .font(.headline)
                if let status {
                    Text(status).font(.callout)
                }
            } footer: {
                Text("""
                    Needs **Full Access**. When installed with a free Apple ID, the app and keyboard \
                    can't share settings, so these are passed over the clipboard once. Open BetterBoard \
                    in any app within 10 minutes to pick them up. Send again after any changes.
                    """)
            }
        }
        .navigationTitle("Shortcuts & your info")
        .onAppear {
            if let data = shortcutsJSON.data(using: .utf8),
               let saved = try? JSONDecoder().decode([ShortcutEntry].self, from: data) {
                shortcuts = saved
            }
        }
        .onChange(of: shortcuts) { _, newValue in
            if let data = try? JSONEncoder().encode(newValue), let text = String(data: data, encoding: .utf8) {
                shortcutsJSON = text
            }
        }
    }

    private func send() {
        var entries: [ShortcutEntry] = []
        for value in [email, email2, phone, address] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { entries.append(ShortcutEntry(shortcut: "", phrase: trimmed)) }
        }
        for entry in shortcuts {
            let phrase = entry.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            let shortcut = entry.shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
            if !phrase.isEmpty { entries.append(ShortcutEntry(shortcut: shortcut, phrase: phrase)) }
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UIPasteboard.general.setItems([["com.leisurp.betterboard.shortcuts": data]], options: [
            .localOnly: true,
            .expirationDate: Date().addingTimeInterval(600),
        ])
        status = "✅ Sent \(entries.count) item\(entries.count == 1 ? "" : "s"). Now open BetterBoard in any app (within 10 minutes)."
    }
}
