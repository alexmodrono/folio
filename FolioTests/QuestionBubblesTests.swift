import AppKit
import PDFKit
import Testing
@testable import Folio

@Suite struct QuestionBubblesTests {
    /// A one-page PDF drawn in memory.
    static func page(width: CGFloat = 612, height: CGFloat = 792) throws -> PDFPage {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 72, y: 72, width: 100, height: 20))
        context.endPDFPage()
        context.closePDF()
        let document = try #require(PDFDocument(data: data as Data))
        return try #require(document.page(at: 0))
    }

    func question(_ bounds: CGRect?) -> AskedQuestion {
        AskedQuestion(anchor: PDFAnchor(document: URL(fileURLWithPath: "/a.pdf"), page: 0, bounds: bounds),
                      quote: "q", question: "", conversation: "/c/1")
    }

    func line(at y: CGFloat) -> CGRect { CGRect(x: 72, y: y, width: 200, height: 12) }

    @Test func bubblesSitInRightMarginInsideCropBox() throws {
        let page = try Self.page()
        let crop = page.bounds(for: .cropBox)
        let bubbles = QuestionAnnotation.bubbles(for: [question(line(at: 500)), question(line(at: 200))], on: page)
        #expect(bubbles.count == 2)
        for bubble in bubbles {
            #expect(crop.contains(bubble.bounds))
            #expect(bubble.bounds.minX > crop.maxX - 40)
            #expect(!bubble.shouldPrint)
        }
        // Next to what they mark: the bubble's top is level with the passage's top.
        let byQuote = Dictionary(uniqueKeysWithValues: bubbles.map { ($0.question.anchor.bounds!.minY, $0.bounds) })
        #expect(abs(byQuote[500]!.maxY - line(at: 500).maxY) < 4)
        #expect(abs(byQuote[200]!.maxY - line(at: 200).maxY) < 4)
    }

    @Test func respectsOffsetCropBox() throws {
        let page = try Self.page()
        let crop = CGRect(x: 50, y: 60, width: 400, height: 500)
        page.setBounds(crop, for: .cropBox)
        let bubbles = QuestionAnnotation.bubbles(for: [question(nil), question(line(at: 300)), question(line(at: 10))], on: page)
        for bubble in bubbles {
            #expect(crop.contains(bubble.bounds), "\(bubble.bounds) outside \(crop)")
        }
    }

    @Test func wholePageQuestionGoesAtTop() throws {
        let page = try Self.page()
        let crop = page.bounds(for: .cropBox)
        let whole = question(nil)
        let bubbles = QuestionAnnotation.bubbles(for: [question(line(at: 300)), whole], on: page)
        let top = try #require(bubbles.first { $0.question.id == whole.id })
        #expect(top.bounds.maxY > crop.maxY - 30)
        #expect(top.bounds.maxY <= crop.maxY)
        #expect(bubbles.allSatisfy { $0.bounds.maxY <= top.bounds.maxY })
    }

    @Test func overlappingQuestionsStack() throws {
        let page = try Self.page()
        let questions = (0..<5).map { _ in question(line(at: 400)) } + [question(line(at: 395)), question(nil), question(nil)]
        let bubbles = QuestionAnnotation.bubbles(for: questions, on: page)
        #expect(bubbles.count == questions.count)
        for (i, a) in bubbles.enumerated() {
            for b in bubbles[(i + 1)...] {
                #expect(!a.bounds.intersects(b.bounds), "\(a.bounds) overlaps \(b.bounds)")
            }
        }
    }

    @Test func passageNearTopIsClampedBelowTopMargin() throws {
        let page = try Self.page()
        let crop = page.bounds(for: .cropBox)
        let bubbles = QuestionAnnotation.bubbles(for: [question(CGRect(x: 72, y: 780, width: 100, height: 12))], on: page)
        #expect(crop.contains(bubbles[0].bounds))
    }

    @Test func nothingGoesBelowBottomMargin() throws {
        let page = try Self.page()
        let crop = page.bounds(for: .cropBox)
        let questions = [question(line(at: 2))] + (0..<80).map { _ in question(line(at: 100)) }
        let bubbles = QuestionAnnotation.bubbles(for: questions, on: page)
        #expect(bubbles.count == questions.count)
        for bubble in bubbles {
            #expect(bubble.bounds.minY >= crop.minY, "\(bubble.bounds) below the page")
            #expect(bubble.bounds.minY >= crop.minY + bubble.bounds.width * 0.4 - 0.001)
        }
    }

    @Test func sizeScalesWithPageWidth() throws {
        let widths: [CGFloat] = [200, 400, 612, 750, 1200, 3000]
        let sizes = try widths.map { width in
            let page = try Self.page(width: width, height: 800)
            return QuestionAnnotation.bubbles(for: [question(nil)], on: page)[0].bounds.width
        }
        #expect(sizes == sizes.sorted())
        #expect(sizes.first! >= 14)
        #expect(sizes.last! <= 22)
        #expect(sizes[2] > sizes[0])
        #expect(sizes[4] > sizes[2])
    }

    @Test func noQuestionsNoBubbles() throws {
        #expect(QuestionAnnotation.bubbles(for: [], on: try Self.page()).isEmpty)
    }
}

@Suite struct CleanTextTests {
    @Test func dehyphenatesAcrossLines() {
        #expect(ReaderViewController.clean("frag-\nment") == "fragment")
        #expect(ReaderViewController.clean("frag-\r\nment") == "fragment")
    }

    @Test func joinsSingleNewlines() {
        #expect(ReaderViewController.clean("one\ntwo\nthree") == "one two three")
        #expect(ReaderViewController.clean("one\r\ntwo") == "one two")
    }

    @Test func keepsParagraphBreaks() {
        #expect(ReaderViewController.clean("para one\ncontinues\n\npara two") == "para one continues\n\npara two")
    }

    @Test func keepsRealHyphens() {
        #expect(ReaderViewController.clean("well-known") == "well-known")
        #expect(ReaderViewController.clean("pages 4 -\n5") == "pages 4 - 5")
    }

    @Test func leavesPlainTextAlone() {
        #expect(ReaderViewController.clean("") == "")
        #expect(ReaderViewController.clean("single line") == "single line")
    }
}
