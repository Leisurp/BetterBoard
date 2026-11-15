import UIKit
import ImageIO

struct GifItem {
    let id: String
    /// Small animated GIF for the grid.
    let previewURL: URL
    /// Larger GIF that gets copied for pasting.
    let shareURL: URL
    let aspectRatio: CGFloat
}

/// Talks to the Giphy API (https://developers.giphy.com).
/// Needs Full Access (internet) and the user's own free API key.
final class GiphyClient {
    enum Failure: Error {
        case badKey
        case offline
        case server
    }

    var apiKey: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 40 * 1024 * 1024)
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private let imageCache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024 // keyboards have a small memory budget
        return cache
    }()

    // MARK: Searching

    func trending(completion: @escaping (Result<[GifItem], Failure>) -> Void) {
        fetch(endpoint: "trending", extra: [], completion: completion)
    }

    func search(_ query: String, completion: @escaping (Result<[GifItem], Failure>) -> Void) {
        fetch(endpoint: "search", extra: [URLQueryItem(name: "q", value: query)], completion: completion)
    }

    private func fetch(endpoint: String, extra: [URLQueryItem],
                       completion: @escaping (Result<[GifItem], Failure>) -> Void) {
        guard let key = apiKey, !key.isEmpty,
              var components = URLComponents(string: "https://api.giphy.com/v1/gifs/\(endpoint)") else {
            completion(.failure(.badKey))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "rating", value: "pg-13"),
            URLQueryItem(name: "lang", value: "en"),
        ] + extra
        guard let url = components.url else {
            completion(.failure(.server))
            return
        }
        session.dataTask(with: url) { data, response, error in
            let result: Result<[GifItem], Failure>
            if error != nil {
                result = .failure(.offline)
            } else if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
                result = .failure(.badKey)
            } else if let data, let items = Self.parse(data) {
                result = .success(items)
            } else {
                result = .failure(.server)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private static func parse(_ data: Data) -> [GifItem]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return nil }
        return list.compactMap { entry in
            guard let id = entry["id"] as? String,
                  let images = entry["images"] as? [String: Any] else { return nil }
            func rendition(_ name: String) -> [String: Any]? { images[name] as? [String: Any] }
            func url(_ r: [String: Any]?) -> URL? { (r?["url"] as? String).flatMap(URL.init(string:)) }

            let preview = rendition("fixed_height_small") ?? rendition("fixed_height")
            guard let previewURL = url(preview),
                  let shareURL = url(rendition("downsized")) ?? url(rendition("original")) ?? url(preview)
            else { return nil }
            let width = Double(preview?["width"] as? String ?? "") ?? 1
            let height = Double(preview?["height"] as? String ?? "") ?? 1
            return GifItem(id: id, previewURL: previewURL, shareURL: shareURL,
                           aspectRatio: CGFloat(max(width, 1) / max(height, 1)))
        }
    }

    // MARK: Images

    /// Loads an animated preview, scaled down to save memory.
    func preview(for url: URL, maxPixel: CGFloat, completion: @escaping (UIImage?) -> Void) {
        if let cached = imageCache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }
        session.dataTask(with: url) { [weak self] data, _, _ in
            var image: UIImage?
            if let data {
                image = AnimatedImage.make(from: data, maxPixel: maxPixel, maxFrames: 24)
            }
            DispatchQueue.main.async {
                if let image, let self {
                    let frames = max(image.images?.count ?? 1, 1)
                    let cost = Int(image.size.width * image.size.height * image.scale * image.scale) * 4 * frames
                    self.imageCache.setObject(image, forKey: url as NSURL, cost: cost)
                }
                completion(image)
            }
        }.resume()
    }

    /// Downloads the full GIF (for copying to the clipboard).
    func download(_ url: URL, completion: @escaping (Data?) -> Void) {
        session.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async { completion(data) }
        }.resume()
    }

    func clearImageCache() {
        imageCache.removeAllObjects()
    }
}

/// Decodes GIF data into an animated UIImage, downsampled and with a capped frame count.
enum AnimatedImage {
    static func make(from data: Data, maxPixel: CGFloat, maxFrames: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        let step = max(1, Int((Double(count) / Double(maxFrames)).rounded(.up)))
        var frames: [UIImage] = []
        var duration: Double = 0
        var index = 0
        while index < count {
            if let cg = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) {
                frames.append(UIImage(cgImage: cg))
            }
            for skipped in index..<min(index + step, count) {
                duration += frameDelay(source, skipped)
            }
            index += step
        }
        if frames.count <= 1 { return frames.first }
        return UIImage.animatedImage(with: frames, duration: max(duration, 0.05 * Double(frames.count)))
    }

    private static func frameDelay(_ source: CGImageSource, _ index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif[kCGImagePropertyGIFDelayTime] as? Double)
            ?? 0.1
        return delay < 0.02 ? 0.1 : delay
    }
}
