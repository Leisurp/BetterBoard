import SwiftUI

@main
struct BetterBoardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Screens the keyboard can link to (betterboard://setup/gifs, betterboard://setup/clipboard).
enum SetupRoute: Hashable {
    case gifs
    case clipboard

    init?(url: URL) {
        guard url.scheme == "betterboard" else { return nil }
        switch url.lastPathComponent {
        case "gifs": self = .gifs
        case "clipboard": self = .clipboard
        default: return nil
        }
    }
}

struct ContentView: View {
    @State private var testText = ""
    @State private var path: [SetupRoute] = []
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section("Set up") {
                    step(1, "Open **Settings › General › Keyboard › Keyboards**.")
                    step(2, "Tap **Add New Keyboard…** and choose **BetterBoard**.")
                    step(3, "Remove the other keyboards except **Emoji**, so the emoji key jumps straight to Apple's emoji keyboard.")
                    step(4, "In any text box, hold the 🌐 globe below the keyboard and pick **BetterBoard**.")
                    Button("Open Settings") { openSettings(openURL) }
                }

                Section("Extras") {
                    NavigationLink(value: SetupRoute.gifs) {
                        Label("GIFs", systemImage: "photo.on.rectangle")
                    }
                    NavigationLink(value: SetupRoute.clipboard) {
                        Label("Clipboard history", systemImage: "list.clipboard")
                    }
                }

                Section("Try it") {
                    TextField("Type here…", text: $testText, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("How it works") {
                    Text("Hold any letter for about a third of a second to type the small symbol in its corner. Let go to insert it.")
                    Text("Slide left or right on the space bar to move the cursor. Slide left from the delete key to delete whole words, and slide back to bring them back.")
                    Text("The buttons at the top left of the keyboard are settings ⚙, GIFs and clipboard history.")
                }
            }
            .navigationTitle("BetterBoard")
            .navigationDestination(for: SetupRoute.self) { route in
                switch route {
                case .gifs: GifSetupView()
                case .clipboard: ClipboardSetupView()
                }
            }
        }
        .onOpenURL { url in
            if let route = SetupRoute(url: url) {
                path = [route]
            }
        }
    }
}

// MARK: - Shared pieces

func openSettings(_ openURL: OpenURLAction) {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        openURL(url)
    }
}

func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text("\(number).")
            .foregroundStyle(.secondary)
            .monospacedDigit()
        Text(text)
    }
}

struct FullAccessSection: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section("Step 1: Turn on Full Access") {
            step(1, "Tap **Open Settings** below.")
            step(2, "Tap **Keyboards**, then turn on **Allow Full Access**.")
            step(3, "iOS shows a standard warning for every keyboard. BetterBoard only uses the internet to search Giphy, and nothing you type leaves your phone.")
            Button("Open Settings") { openSettings(openURL) }
        }
    }
}

// MARK: - GIFs

struct GifSetupView: View {
    @AppStorage("giphyKey") private var savedKey = ""
    @State private var key = ""
    @State private var status: String?
    @State private var checking = false
    @Environment(\.openURL) private var openURL

    /// Must match ClipboardStore.giphyKeyPrefix in the keyboard.
    private let handoffPrefix = "BetterBoard-Giphy-Key:"

    var body: some View {
        Form {
            Section {
                Text("""
                    Keyboards on iPhone can't use the internet or copy images unless you turn on \
                    **Full Access**. GIFs also come from **Giphy**, which gives each app its own free key. \
                    It's a one-time setup, about 2 minutes.
                    """)
            } header: {
                Text("Why this is needed")
            }

            FullAccessSection()

            Section("Step 2: Get a free Giphy key") {
                step(1, "Open the Giphy developer site (button below) and **sign up** or log in. It's free.")
                step(2, "Tap **Create an App**, choose **API** (not SDK), and give it any name, like *BetterBoard*.")
                step(3, "Copy the **API Key** it shows you.")
                Button("Open Giphy developer site") {
                    if let url = URL(string: "https://developers.giphy.com/dashboard/") { openURL(url) }
                }
            }

            Section {
                TextField("Paste your API key here", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                Button {
                    save()
                } label: {
                    if checking {
                        ProgressView()
                    } else {
                        Text("Save and send to keyboard")
                    }
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                if let status {
                    Text(status).font(.callout)
                }
            } header: {
                Text("Step 3: Add the key")
            } footer: {
                Text("""
                    When installed with a free Apple ID, the app and keyboard can't share settings \
                    directly, so the key is passed over the clipboard once. The keyboard picks it up \
                    the next time you open it, then removes it from the clipboard.
                    """)
            }

            Section("Step 4: Use it") {
                step(1, "Open any app with a text box and switch to BetterBoard.")
                step(2, "Tap **GIF** at the top left. Tap a GIF to copy it, then tap the text box and choose **Paste**.")
                Text("iPhone keyboards can only type text, so GIFs are copied for you to paste. Gboard on iPhone works the same way.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("GIFs")
        .onAppear { if key.isEmpty { key = savedKey } }
    }

    private func save() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://api.giphy.com/v1/gifs/trending?limit=1&api_key=\(trimmed)") else {
            status = "That doesn't look like a valid key."
            return
        }
        checking = true
        status = nil
        URLSession.shared.dataTask(with: url) { _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                checking = false
                if error != nil {
                    status = "Couldn't reach Giphy. Check your internet connection and try again."
                } else if code == 200 {
                    savedKey = trimmed
                    UIPasteboard.general.string = handoffPrefix + trimmed
                    status = "✅ Key works and has been sent. Now open BetterBoard in any app and tap GIF."
                } else {
                    status = "Giphy didn't accept that key (error \(code)). Copy it again from the Giphy site."
                }
            }
        }.resume()
    }
}

// MARK: - Clipboard

struct ClipboardSetupView: View {
    var body: some View {
        Form {
            Section {
                Text("""
                    Keyboards on iPhone can only see your clipboard when **Full Access** is on, and only \
                    while the keyboard is on screen. BetterBoard saves what's on your clipboard each \
                    time the keyboard opens, plus anything you copy while it's open.
                    """)
            } header: {
                Text("Why this is needed")
            }

            FullAccessSection()

            Section("Step 2: Use it") {
                step(1, "Tap the **clipboard** button at the top left of the keyboard.")
                step(2, "Tap an item to paste it. Swipe left to delete, or tap the pin to keep it.")
                step(3, "If iOS asks **Allow Paste?**, choose **Allow**. You can stop it asking in **Settings › Apps › BetterBoard › Paste from Other Apps**.")
            }

            Section("Privacy") {
                Text("History stays on your phone. Passwords copied from password managers are skipped, and up to 30 unpinned items are kept.")
            }
        }
        .navigationTitle("Clipboard history")
    }
}
