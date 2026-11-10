import CoreGraphics
import Foundation

/// Where in a PDF something was asked about: a passage on a page, or the whole page.
nonisolated struct PDFAnchor: Codable, Equatable, Sendable {
    var document: String
    /// Zero-based page index.
    var page: Int
    /// The passage's bounds in page space. Nil for the whole page.
    var bounds: CGRect?

    var isWholePage: Bool { bounds == nil }

    /// What the bridge carries with a pending selection and hands back when the message is sent.
    var bridgeValue: [String: Any] {
        var value: [String: Any] = ["document": document, "page": page]
        if let bounds {
            value["bounds"] = [bounds.minX, bounds.minY, bounds.width, bounds.height]
        }
        return value
    }

    init(document: URL, page: Int, bounds: CGRect?) {
        self.document = document.standardizedFileURL.path
        self.page = page
        self.bounds = bounds
    }

    init?(bridgeValue: Any?) {
        guard let value = bridgeValue as? [String: Any],
              let document = value["document"] as? String,
              let page = (value["page"] as? NSNumber)?.intValue else { return nil }
        self.document = document
        self.page = page
        if let numbers = value["bounds"] as? [NSNumber], numbers.count == 4 {
            bounds = CGRect(x: numbers[0].doubleValue, y: numbers[1].doubleValue,
                            width: numbers[2].doubleValue, height: numbers[3].doubleValue)
        }
    }
}

/// Something the person asked ChatGPT about a PDF, shown as a bubble on the page.
nonisolated struct AskedQuestion: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var anchor: PDFAnchor
    /// The quoted passage, or the page's text for a whole page.
    var quote: String
    /// What the person typed with it. Can be empty.
    var question: String
    /// The chatgpt.com path of the conversation, such as "/c/…".
    var conversation: String
    var date = Date()
}

/// Every asked question, saved in Folio's own data. PDFs are never written to.
final class QuestionStore {
    static let shared = QuestionStore()
    static let didChange = Notification.Name("QuestionStore.didChange")

    private(set) var questions: [AskedQuestion] = []
    private let file: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Folio", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        file = support.appendingPathComponent("questions.json")
        if let data = try? Data(contentsOf: file) {
            questions = (try? JSONDecoder().decode([AskedQuestion].self, from: data)) ?? []
        }
    }

    func questions(for document: URL) -> [AskedQuestion] {
        let path = document.standardizedFileURL.path
        return questions.filter { $0.anchor.document == path }
    }

    func add(_ new: [AskedQuestion]) {
        guard !new.isEmpty else { return }
        questions.append(contentsOf: new)
        save()
    }

    func remove(_ id: AskedQuestion.ID) {
        questions.removeAll { $0.id == id }
        save()
    }

    /// Keeps questions with their file when Folio renames or moves it, or a folder above it.
    func moveDocuments(from old: URL, to new: URL) {
        let oldPath = old.standardizedFileURL.path
        let newPath = new.standardizedFileURL.path
        var changed = false
        for index in questions.indices {
            let path = questions[index].anchor.document
            if path == oldPath {
                questions[index].anchor.document = newPath
                changed = true
            } else if path.hasPrefix(oldPath + "/") {
                questions[index].anchor.document = newPath + path.dropFirst(oldPath.count)
                changed = true
            }
        }
        if changed { save() }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(questions).write(to: file, options: .atomic)
        } catch {
            NSLog("Folio: couldn't save questions: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
