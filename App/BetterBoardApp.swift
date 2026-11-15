import SwiftUI

@main
struct BetterBoardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var testText = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section("Set up") {
                    step(1, "Open **Settings › General › Keyboard › Keyboards**.")
                    step(2, "Tap **Add New Keyboard…** and choose **BetterBoard**.")
                    step(3, "Remove the other keyboards except **Emoji**, so the emoji key jumps straight to Apple's emoji keyboard.")
                    step(4, "In any text box, hold the 🌐 globe below the keyboard and pick **BetterBoard**.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }

                Section("Try it") {
                    TextField("Type here…", text: $testText, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("How it works") {
                    Text("Hold any letter for about a third of a second to type the small symbol in its corner. Let go to insert it.")
                    Text("Tap ⚙ at the left of the suggestion bar for keyboard settings.")
                }
            }
            .navigationTitle("BetterBoard")
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(text)
        }
    }
}
