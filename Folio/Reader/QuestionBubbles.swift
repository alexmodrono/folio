import AppKit
import PDFKit
import SwiftUI

/// A bubble in the page's right margin marking something asked about there. Drawn by Folio, never saved
/// into the PDF and never printed.
nonisolated final class QuestionAnnotation: PDFAnnotation {
    private(set) var question: AskedQuestion!

    convenience init(question: AskedQuestion, bounds: CGRect) {
        self.init(bounds: bounds, forType: .stamp, withProperties: nil)
        self.question = question
        shouldPrint = false
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let tail = rect.height * 0.22
        let body = CGRect(x: rect.minX, y: rect.minY + tail, width: rect.width, height: rect.height - tail)
        let radius = body.height * 0.32

        let path = CGMutablePath()
        path.addRoundedRect(in: body, cornerWidth: radius, cornerHeight: radius)
        path.move(to: CGPoint(x: body.minX + rect.width * 0.22, y: body.minY + 0.5))
        path.addLine(to: CGPoint(x: body.minX + rect.width * 0.16, y: rect.minY))
        path.addLine(to: CGPoint(x: body.minX + rect.width * 0.42, y: body.minY + 0.5))
        path.closeSubpath()

        context.saveGState()
        context.addPath(path)
        context.setFillColor(NSColor.controlAccentColor.cgColor)
        context.fillPath()

        // Two lines of "text" inside the bubble.
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(max(1, body.height * 0.11))
        context.setLineCap(.round)
        let inset = body.width * 0.26
        for (offset, length) in [(0.62, 1.0), (0.36, 0.62)] {
            let y = body.minY + body.height * offset
            context.move(to: CGPoint(x: body.minX + inset, y: y))
            context.addLine(to: CGPoint(x: body.minX + inset + (body.width - inset * 2) * length, y: y))
        }
        context.strokePath()
        context.restoreGState()
    }

    /// Bubbles for one page, in the right margin next to what they mark, stacked so none overlap.
    static func bubbles(for questions: [AskedQuestion], on page: PDFPage) -> [QuestionAnnotation] {
        let crop = page.bounds(for: .cropBox)
        let size = max(14, min(22, crop.width * 0.026))
        let margin = size * 0.4
        var placed: [QuestionAnnotation] = []
        var lowest = CGFloat.infinity
        let ordered = questions.sorted { top(of: $0, in: crop) > top(of: $1, in: crop) }
        for question in ordered {
            var y = min(top(of: question, in: crop) - size, crop.maxY - margin - size)
            if y > lowest - size - 2 { y = lowest - size - 2 }
            y = max(y, crop.minY + margin)
            lowest = y
            let frame = CGRect(x: crop.maxX - margin - size, y: y, width: size, height: size * 0.9)
            placed.append(QuestionAnnotation(question: question, bounds: frame))
        }
        return placed
    }

    private static func top(of question: AskedQuestion, in crop: CGRect) -> CGFloat {
        question.anchor.bounds?.maxY ?? crop.maxY
    }
}

/// What a bubble shows when clicked: the passage, the question, and a way back to the conversation.
struct QuestionPopover: View {
    let question: AskedQuestion
    let onShow: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Group {
                if question.anchor.isWholePage {
                    Text("Page \(question.anchor.page + 1)")
                        .font(.headline)
                } else {
                    Text(question.quote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(.leading, Theme.Space.s)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(.quaternary).frame(width: 2)
                        }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if !question.question.isEmpty {
                Text(question.question)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Show in Chat", action: onShow)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete")
                .accessibilityLabel("Delete")
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 300, alignment: .leading)
    }
}
