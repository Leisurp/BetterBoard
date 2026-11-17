import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Must match CustomThemeData in the keyboard.
struct CustomThemeData: Codable {
    var background: String
    var key: String
    var border: String?
    var label: String
    var hasImage: Bool
}

/// Make your own keyboard theme: a photo from your library and/or your own colours
/// for the background, keys, key outlines and letters (like Gboard's custom themes).
struct ThemeEditorView: View {
    @AppStorage("themeBackground") private var backgroundHex = "2B2B2EFF"
    @AppStorage("themeKey") private var keyHex = "48484CFF"
    @AppStorage("themeBorderOn") private var borderOn = false
    @AppStorage("themeBorder") private var borderHex = "FFFFFF66"
    @AppStorage("themeLabel") private var labelHex = "FFFFFFFF"
    @AppStorage("themeDarken") private var darken = 0.25
    @AppStorage("themePosition") private var position = 0.5

    @State private var showPicker = false
    @State private var loadingPhoto = false
    @State private var photoMessage: String?
    @State private var photo: UIImage? = ThemePhotoFile.load()
    @State private var status: String?

    /// Width ÷ height of the keyboard (suggestion bar + keys) on iPhone.
    static let keyboardAspect: CGFloat = 1.7

    var body: some View {
        Form {
            Section {
                preview
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("A preview of your keyboard.")
            }

            Section("Background photo") {
                Button {
                    showPicker = true
                } label: {
                    Label(photo == nil ? "Choose a photo" : "Choose a different photo", systemImage: "photo")
                }
                if loadingPhoto {
                    HStack {
                        ProgressView()
                        Text("Loading photo…").foregroundStyle(.secondary)
                    }
                }
                if let photoMessage {
                    Text(photoMessage).font(.callout)
                }
                if photo != nil {
                    LabeledContent("Position") {
                        Slider(value: $position, in: 0...1)
                    }
                    LabeledContent("Darken") {
                        Slider(value: $darken, in: 0...0.8)
                    }
                    Button("Remove photo", role: .destructive) {
                        photo = nil
                        photoMessage = nil
                        ThemePhotoFile.delete()
                    }
                }
            }

            Section {
                ColorPicker("Background", selection: colorBinding($backgroundHex), supportsOpacity: false)
                ColorPicker("Keys", selection: colorBinding($keyHex), supportsOpacity: true)
                Toggle("Key outlines", isOn: $borderOn)
                if borderOn {
                    ColorPicker("Outline colour", selection: colorBinding($borderHex), supportsOpacity: true)
                }
                ColorPicker("Letters", selection: colorBinding($labelHex), supportsOpacity: false)
            } header: {
                Text("Colours")
            } footer: {
                Text("Drag the opacity slider in the Keys colour picker to make keys see-through over your photo.")
            }

            Section("Quick styles") {
                Button("See-through keys (for photos)") {
                    keyHex = "FFFFFF33"; borderOn = true; borderHex = "FFFFFF80"; labelHex = "FFFFFFFF"
                }
                Button("No keys, just letters") {
                    keyHex = "FFFFFF00"; borderOn = false; labelHex = "FFFFFFFF"
                }
                Button("Solid dark keys") {
                    keyHex = "2C2C2EFF"; borderOn = false; labelHex = "FFFFFFFF"
                }
                Button("Solid light keys") {
                    keyHex = "FFFFFFFF"; borderOn = false; labelHex = "000000FF"
                }
            }

            Section {
                Button("Start over", role: .destructive) {
                    backgroundHex = "2B2B2EFF"; keyHex = "48484CFF"; borderOn = false
                    borderHex = "FFFFFF66"; labelHex = "FFFFFFFF"; darken = 0.25; position = 0.5
                    photo = nil
                    photoMessage = nil
                    status = nil
                    ThemePhotoFile.delete()
                }
            } footer: {
                Text("Clears the photo and colours here. To put the keyboard back to the standard Apple look, open ⚙ settings in the keyboard and tap **Reset to the standard look**.")
            }

            Section {
                Button("Apply to keyboard") { apply() }
                    .font(.headline)
                if let status {
                    Text(status).font(.callout)
                }
            } footer: {
                Text("""
                    Needs **Full Access** (the same as GIFs). When installed with a free Apple ID, the app \
                    and keyboard can't share files, so your theme is passed over the clipboard once. Open \
                    BetterBoard in any app within 10 minutes and it switches to your theme. You can switch \
                    back any time in the keyboard's ⚙ settings under Theme.
                    """)
            }
        }
        .navigationTitle("Custom theme")
        .sheet(isPresented: $showPicker) {
            PhotoPicker { provider in
                showPicker = false
                guard let provider else { return }
                loadingPhoto = true
                photoMessage = nil
                PhotoPicker.loadImage(from: provider) { image in
                    loadingPhoto = false
                    guard let image else {
                        photoMessage = "⚠️ Couldn't open that photo. If it's stored in iCloud, open it in Photos first so it downloads, then try again."
                        return
                    }
                    let small = ThemePhotoFile.downscale(image, maxSide: 1800)
                    ThemePhotoFile.save(small)
                    photo = small
                    position = 0.5
                    // Solid keys would hide the photo, so switch to see-through keys.
                    if UIColor(hex: keyHex).cgColor.alpha > 0.6 {
                        keyHex = "FFFFFF33"; borderOn = true; borderHex = "FFFFFF80"; labelHex = "FFFFFFFF"
                        photoMessage = "✅ Photo added (\(Int(small.size.width))×\(Int(small.size.height))). Keys switched to see-through so it shows. Change them below if you like."
                    } else {
                        photoMessage = "✅ Photo added (\(Int(small.size.width))×\(Int(small.size.height)))."
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Preview

    private var preview: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack {
                Color(uiColor: UIColor(hex: backgroundHex))
                if let photo {
                    Image(uiImage: Self.render(photo: photo, width: width * 2, position: position, darken: darken))
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: width / Self.keyboardAspect)
                        .clipped()
                }
                VStack(spacing: 7) {
                    Spacer(minLength: 18)
                    keyRow("QWERTYUIOP", width: width)
                    keyRow("ASDFGHJKL", width: width)
                    keyRow("ZXCVBNM", width: width)
                    keyRow(" ", width: width, space: true)
                }
                .padding(.bottom, 8)
            }
            .frame(width: width, height: width / Self.keyboardAspect)
        }
        .aspectRatio(Self.keyboardAspect, contentMode: .fit)
    }

    private func keyRow(_ letters: String, width: CGFloat, space: Bool = false) -> some View {
        let keyWidth = (width - 12 - 9 * 5) / 10
        return HStack(spacing: 5) {
            ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(uiColor: UIColor(hex: keyHex)))
                    if borderOn {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color(uiColor: UIColor(hex: borderHex)), lineWidth: 1)
                    }
                    Text(String(letter))
                        .font(.system(size: keyWidth * 0.55))
                        .foregroundStyle(Color(uiColor: UIColor(hex: labelHex)))
                }
                .frame(width: space ? keyWidth * 5 : keyWidth)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Apply

    private func apply() {
        let theme = CustomThemeData(background: backgroundHex,
                                    key: keyHex,
                                    border: borderOn ? borderHex : nil,
                                    label: labelHex,
                                    hasImage: photo != nil)
        guard let json = try? JSONEncoder().encode(theme) else { return }
        var item: [String: Any] = ["com.leisurp.betterboard.theme": json]
        if let photo,
           let jpeg = Self.render(photo: photo, width: 1320, position: position, darken: darken)
               .jpegData(compressionQuality: 0.85) {
            item["com.leisurp.betterboard.theme-image"] = jpeg
        }
        let sentPhoto = item["com.leisurp.betterboard.theme-image"] != nil
        UIPasteboard.general.setItems([item], options: [
            .localOnly: true,
            .expirationDate: Date().addingTimeInterval(600),
        ])
        status = sentPhoto
            ? "✅ Sent with your photo. Now open BetterBoard in any app (within 10 minutes) and it'll switch to your theme."
            : "✅ Sent (colours only, no photo). Now open BetterBoard in any app within 10 minutes."
    }

    /// The photo cropped to the keyboard's shape, with the darkening baked in.
    static func render(photo: UIImage, width: CGFloat, position: Double, darken: Double) -> UIImage {
        let width = max(width, 10) // the preview can be measured as 0 wide at first
        let size = CGSize(width: width.rounded(), height: (width / keyboardAspect).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let scale = max(size.width / photo.size.width, size.height / photo.size.height)
            let drawn = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
            // Position slides along whichever side overflows.
            let x = (size.width - drawn.width) * position
            let y = (size.height - drawn.height) * position
            photo.draw(in: CGRect(origin: CGPoint(x: x, y: y), size: drawn))
            // Darken on top of the photo. (Plain `context.fill` *replaces* the pixels
            // underneath, which wiped the photo out completely.)
            UIColor.black.withAlphaComponent(darken).setFill()
            context.fill(CGRect(origin: .zero, size: size), blendMode: .normal)
        }
    }

    private func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: { Color(uiColor: UIColor(hex: hex.wrappedValue)) },
            set: { hex.wrappedValue = UIColor($0).hexString }
        )
    }
}

/// The chosen photo, kept in the app so you can tweak the theme later.
enum ThemePhotoFile {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("theme-photo.jpg")
    }

    static func load() -> UIImage? {
        UIImage(contentsOfFile: url.path)
    }

    static func save(_ image: UIImage) {
        try? image.jpegData(compressionQuality: 0.9)?.write(to: url, options: .atomic)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }

    static func downscale(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

extension UIColor {
    /// "RRGGBBAA" (or "RRGGBB").
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        if hex.count == 6 { value = (value << 8) | 0xFF }
        self.init(red: CGFloat((value >> 24) & 0xFF) / 255,
                  green: CGFloat((value >> 16) & 0xFF) / 255,
                  blue: CGFloat((value >> 8) & 0xFF) / 255,
                  alpha: CGFloat(value & 0xFF) / 255)
    }

    var hexString: String {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let converted = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil) ?? cgColor
        var parts = (converted.components ?? [0, 0, 0, 1]).map { min(max($0, 0), 1) }
        if parts.count == 2 { parts = [parts[0], parts[0], parts[0], parts[1]] }
        while parts.count < 4 { parts.append(1) }
        return parts.prefix(4).map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }
}

/// Apple's photo picker (no permission needed: you only share the photo you pick).
struct PhotoPicker: UIViewControllerRepresentable {
    var onFinish: (NSItemProvider?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onFinish: (NSItemProvider?) -> Void
        init(onFinish: @escaping (NSItemProvider?) -> Void) { self.onFinish = onFinish }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onFinish(results.first?.itemProvider)
        }
    }

    /// Loads the picked photo, trying the image itself first and then its raw data
    /// (covers HEIC, ProRAW, screenshots…). Calls back on the main thread.
    static func loadImage(from provider: NSItemProvider, completion: @escaping (UIImage?) -> Void) {
        func finish(_ image: UIImage?) {
            DispatchQueue.main.async { completion(image) }
        }
        func loadData() {
            let type = provider.registeredTypeIdentifiers.first {
                UTType($0)?.conforms(to: .image) ?? false
            } ?? UTType.image.identifier
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                finish(data.flatMap { UIImage(data: $0) })
            }
        }
        if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    finish(image)
                } else {
                    loadData()
                }
            }
        } else {
            loadData()
        }
    }
}
