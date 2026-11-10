import CoreGraphics
import Foundation
import Testing
@testable import Folio

@Suite struct QuestionStoreTests {
    let folder: URL
    let file: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("FolioTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = folder.appendingPathComponent("questions.json")
    }

    func question(_ path: String, page: Int = 0, bounds: CGRect? = nil, quote: String = "q") -> AskedQuestion {
        AskedQuestion(
            anchor: PDFAnchor(document: URL(fileURLWithPath: path), page: page, bounds: bounds),
            quote: quote, question: "why?", conversation: "/c/abc"
        )
    }

    func documents(_ store: QuestionStore) -> [String] {
        store.questions.map(\.anchor.document)
    }

    @Test func startsEmptyWithoutFile() {
        #expect(QuestionStore(file: file).questions.isEmpty)
    }

    @Test func addPersistsAndReloads() {
        let store = QuestionStore(file: file)
        let a = question("/lib/a.pdf", page: 2, bounds: CGRect(x: 10, y: 20, width: 30, height: 40))
        let b = question("/lib/b.pdf")
        store.add([a, b])
        #expect(store.questions == [a, b])
        #expect(FileManager.default.fileExists(atPath: file.path))

        let reloaded = QuestionStore(file: file)
        #expect(reloaded.questions.count == 2)
        #expect(reloaded.questions.map(\.id) == [a.id, b.id])
        #expect(reloaded.questions[0].anchor == a.anchor)
        #expect(reloaded.questions[0].quote == a.quote)
        #expect(reloaded.questions[1].anchor.isWholePage)
    }

    @Test func addingNothingDoesntWrite() {
        QuestionStore(file: file).add([])
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func removePersists() {
        let store = QuestionStore(file: file)
        let a = question("/lib/a.pdf"), b = question("/lib/b.pdf")
        store.add([a, b])
        store.remove(a.id)
        #expect(store.questions.map(\.id) == [b.id])
        #expect(QuestionStore(file: file).questions.map(\.id) == [b.id])
    }

    @Test func corruptFileLoadsEmpty() throws {
        try Data("not json".utf8).write(to: file)
        #expect(QuestionStore(file: file).questions.isEmpty)
    }

    @Test func questionsForDocument() {
        let store = QuestionStore(file: file)
        let a1 = question("/lib/a.pdf", page: 0), a2 = question("/lib/a.pdf", page: 3), b = question("/lib/b.pdf")
        store.add([a1, b, a2])
        #expect(store.questions(for: URL(fileURLWithPath: "/lib/a.pdf")).map(\.id) == [a1.id, a2.id])
        // Paths are standardized on both sides.
        #expect(store.questions(for: URL(fileURLWithPath: "/lib/./sub/../b.pdf")).map(\.id) == [b.id])
        #expect(store.questions(for: URL(fileURLWithPath: "/lib/c.pdf")).isEmpty)
    }

    @Test func moveFile() {
        let store = QuestionStore(file: file)
        store.add([question("/lib/a.pdf"), question("/lib/ab.pdf"), question("/lib/b.pdf")])
        store.moveDocuments(from: URL(fileURLWithPath: "/lib/a.pdf"), to: URL(fileURLWithPath: "/lib/renamed.pdf"))
        #expect(documents(store) == ["/lib/renamed.pdf", "/lib/ab.pdf", "/lib/b.pdf"])
        #expect(documents(QuestionStore(file: file)) == ["/lib/renamed.pdf", "/lib/ab.pdf", "/lib/b.pdf"])
    }

    @Test func moveFolderLeavesSiblingWithSharedPrefix() {
        let store = QuestionStore(file: file)
        store.add([
            question("/a/b/one.pdf"),
            question("/a/b/deep/two.pdf"),
            question("/a/bc/three.pdf"),
            question("/a/b"),
        ])
        store.moveDocuments(from: URL(fileURLWithPath: "/a/b"), to: URL(fileURLWithPath: "/x/y"))
        let expected = ["/x/y/one.pdf", "/x/y/deep/two.pdf", "/a/bc/three.pdf", "/x/y"]
        #expect(documents(store) == expected)
        #expect(documents(QuestionStore(file: file)) == expected)
    }

    @Test func moveWithNoMatchDoesntWrite() {
        let store = QuestionStore(file: file)
        store.moveDocuments(from: URL(fileURLWithPath: "/nope"), to: URL(fileURLWithPath: "/else"))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func removeDocumentsUnderFileAndFolder() {
        let store = QuestionStore(file: file)
        store.add([
            question("/a/b/one.pdf"),
            question("/a/b/deep/two.pdf"),
            question("/a/bc/three.pdf"),
            question("/a/other.pdf"),
        ])
        store.removeDocuments(under: URL(fileURLWithPath: "/a/other.pdf"))
        #expect(documents(store) == ["/a/b/one.pdf", "/a/b/deep/two.pdf", "/a/bc/three.pdf"])
        store.removeDocuments(under: URL(fileURLWithPath: "/a/b"))
        #expect(documents(store) == ["/a/bc/three.pdf"])
        #expect(documents(QuestionStore(file: file)) == ["/a/bc/three.pdf"])
    }
}

@Suite struct PDFAnchorTests {
    @Test func bridgeValueRoundTripWithBounds() throws {
        let anchor = PDFAnchor(document: URL(fileURLWithPath: "/lib/x/../a.pdf"), page: 4,
                               bounds: CGRect(x: 1.5, y: 2, width: 300.25, height: 12))
        #expect(anchor.document == "/lib/a.pdf")
        #expect(!anchor.isWholePage)
        let value = anchor.bridgeValue
        #expect(value["bounds"] as? [CGFloat] == [1.5, 2, 300.25, 12])
        #expect(PDFAnchor(bridgeValue: value) == anchor)
    }

    @Test func bridgeValueRoundTripWholePage() {
        let anchor = PDFAnchor(document: URL(fileURLWithPath: "/lib/a.pdf"), page: 0, bounds: nil)
        #expect(anchor.isWholePage)
        #expect(anchor.bridgeValue["bounds"] == nil)
        #expect(PDFAnchor(bridgeValue: anchor.bridgeValue) == anchor)
    }

    /// What comes back from JavaScript: numbers as NSNumber, through JSON.
    @Test func bridgeValueThroughJSON() throws {
        let anchor = PDFAnchor(document: URL(fileURLWithPath: "/lib/a.pdf"), page: 7,
                               bounds: CGRect(x: 10, y: 20, width: 30, height: 40))
        let json = try JSONSerialization.data(withJSONObject: anchor.bridgeValue)
        let decoded = try JSONSerialization.jsonObject(with: json)
        #expect(PDFAnchor(bridgeValue: decoded) == anchor)
    }

    @Test func invalidBridgeValues() {
        #expect(PDFAnchor(bridgeValue: nil) == nil)
        #expect(PDFAnchor(bridgeValue: "x") == nil)
        #expect(PDFAnchor(bridgeValue: ["page": 1]) == nil)
        #expect(PDFAnchor(bridgeValue: ["document": "/a.pdf"]) == nil)
        // Malformed bounds fall back to the whole page.
        let partial = PDFAnchor(bridgeValue: ["document": "/a.pdf", "page": 1, "bounds": [1, 2]])
        #expect(partial?.isWholePage == true)
    }
}
