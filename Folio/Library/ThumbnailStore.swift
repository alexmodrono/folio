import AppKit
import CryptoKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct DocumentPreview: @unchecked Sendable {
    let image: CGImage?
    let pageCount: Int
}

/// First-page thumbnails and page counts. Rendered off the main thread, cached in memory and on disk.
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private final class Box {
        let preview: DocumentPreview
        init(_ preview: DocumentPreview) { self.preview = preview }
    }

    private let memory = NSCache<NSString, Box>()
    private var inFlight: [String: Task<DocumentPreview, Never>] = [:]
    private let directory: URL

    private init() {
        memory.countLimit = 400
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Folio", isDirectory: true)
            .appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cached(for url: URL, modified: Date) -> DocumentPreview? {
        memory.object(forKey: Self.key(url, modified) as NSString)?.preview
    }

    func preview(for url: URL, modified: Date) async -> DocumentPreview {
        let key = Self.key(url, modified)
        if let box = memory.object(forKey: key as NSString) { return box.preview }
        if let running = inFlight[key] { return await running.value }

        let directory = self.directory
        let task = Task.detached(priority: .userInitiated) {
            Self.load(url: url, key: key, directory: directory)
        }
        inFlight[key] = task
        let preview = await task.value
        inFlight[key] = nil
        memory.setObject(Box(preview), forKey: key as NSString)
        return preview
    }

    nonisolated private static func key(_ url: URL, _ modified: Date) -> String {
        let digest = SHA256.hash(data: Data("\(url.path)|\(modified.timeIntervalSince1970)".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func load(url: URL, key: String, directory: URL) -> DocumentPreview {
        let file = directory.appendingPathComponent(key + ".png")
        // The page count is cached beside the image, so a cached preview never opens the PDF.
        let countFile = directory.appendingPathComponent(key + ".pages")

        if let source = CGImageSourceCreateWithURL(file as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
           let count = (try? String(contentsOf: countFile, encoding: .utf8)).flatMap(Int.init) {
            return DocumentPreview(image: image, pageCount: count)
        }
        let pageCount = CGPDFDocument(url as CFURL)?.numberOfPages ?? 0

        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
            return DocumentPreview(image: nil, pageCount: pageCount)
        }
        var size = page.bounds(for: .cropBox).size
        if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        let width: CGFloat = 720
        let target = NSSize(width: width, height: (width * size.height / max(size.width, 1)).rounded())
        let thumbnail = page.thumbnail(of: target, for: .cropBox)
        guard let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return DocumentPreview(image: nil, pageCount: document.pageCount)
        }
        if let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        try? String(document.pageCount).write(to: countFile, atomically: true, encoding: .utf8)
        return DocumentPreview(image: image, pageCount: document.pageCount)
    }
}
