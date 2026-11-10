import SwiftUI

/// Design tokens. Colors come from semantic system colors so light, dark and increased contrast work.
nonisolated enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    static let cardRadius: CGFloat = 16
    static let pillRadius: CGFloat = 10
    /// The chat card in the inspector column.
    static let panelRadius: CGFloat = 12
    static let panelHeaderHeight: CGFloat = 44
    /// Width divided by height for every card in the grid.
    static let cardAspect: CGFloat = 0.95
    static let gridMinimum: CGFloat = 200
    static let gridMaximum: CGFloat = 300

    static let canvas = Color(nsColor: .textBackgroundColor)
    static let hairline = Color(nsColor: .separatorColor)
    static let folderFill = Color(nsColor: .tertiarySystemFill)

    static let cardTitle = Font.system(size: 15, weight: .semibold)
    static let cardDetail = Font.system(size: 13)
    static let tab = Font.system(size: 14, weight: .medium)
}

extension View {
    /// The card surface: canvas fill, hairline border, faint shadow.
    func cardSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        return background(Theme.canvas)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }
}
