import SwiftUI

/// Loads a document's first-page preview once and hands it to `content`.
/// Placeholders get no preview: reading one would download it.
private struct PreviewLoader<Content: View>: View {
    let node: LibraryNode
    @ViewBuilder let content: (DocumentPreview?) -> Content
    @State private var preview: DocumentPreview?

    var body: some View {
        if node.isPlaceholder {
            content(nil)
        } else {
            content(preview ?? ThumbnailStore.shared.cached(for: node.url, modified: node.modified))
                .task(id: "\(node.id)|\(node.modified.timeIntervalSince1970)") {
                    preview = await ThumbnailStore.shared.preview(for: node.url, modified: node.modified)
                }
        }
    }
}

/// A page image filling its frame, aligned to the top of the page.
private struct PageImage: View {
    let image: CGImage?
    var isPlaceholder = false

    var body: some View {
        GeometryReader { proxy in
            if isPlaceholder {
                Color.white.overlay {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: min(proxy.size.width, proxy.size.height) * 0.22))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            } else if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .clipped()
            } else {
                Color.white
            }
        }
    }
}

private func detailText(_ node: LibraryNode, _ preview: DocumentPreview?) -> String {
    if node.isPlaceholder { return String(localized: "Not downloaded") }
    guard let count = preview?.pageCount, count > 0 else { return " " }
    return String(localized: "\(count) pages")
}

struct DocumentCard: View {
    let node: LibraryNode

    var body: some View {
        PreviewLoader(node: node) { preview in
            Color.clear
                .aspectRatio(Theme.cardAspect, contentMode: .fit)
                .overlay {
                    VStack(spacing: 0) {
                        PageImage(image: preview?.image, isPlaceholder: node.isPlaceholder)
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        CardFooter(title: node.name, detail: detailText(node, preview))
                    }
                    .cardSurface()
                }
        }
    }
}

struct FolderCard: View {
    let node: LibraryNode

    var body: some View {
        // Prefer downloaded documents, which have a page to show.
        let documents = node.allDocuments
        let papers = Array((documents.filter { !$0.isPlaceholder } + documents.filter(\.isPlaceholder)).prefix(2))
        Color.clear
            .aspectRatio(Theme.cardAspect, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    ZStack(alignment: .top) {
                        FolderShape()
                            .fill(Theme.folderFill)
                        // Back paper sits higher and narrower than the front one.
                        ForEach(Array(papers.enumerated().reversed()), id: \.element.id) { index, paper in
                            let inset: CGFloat = index == 0 ? 24 : 40
                            Paper(node: paper)
                                .frame(width: width - inset * 2, height: height * 0.62)
                                .offset(y: index == 0 ? 44 : 32)
                        }
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            CardFooter(title: node.name, detail: itemCount)
                                .frame(height: height * 0.42, alignment: .bottomLeading)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                        .strokeBorder(Theme.hairline, lineWidth: 1)
                                )
                        }
                    }
                }
            }
    }

    private var itemCount: String {
        let count = node.children.count
        return String(localized: "\(count) items")
    }
}

private struct Paper: View {
    let node: LibraryNode

    var body: some View {
        PreviewLoader(node: node) { preview in
            PageImage(image: preview?.image, isPlaceholder: node.isPlaceholder)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
        }
    }
}

private struct CardFooter: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.cardTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(detail)
                .font(Theme.cardDetail)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.l + 4)
        .padding(.vertical, Theme.Space.l)
    }
}

/// A folder silhouette: a tab on the top left that slopes into the body.
private nonisolated struct FolderShape: Shape {
    var radius: CGFloat = Theme.cardRadius
    var tabHeight: CGFloat = 18
    var tabWidthRatio: CGFloat = 0.4

    func path(in rect: CGRect) -> Path {
        let tabWidth = rect.width * tabWidthRatio
        let slope: CGFloat = 16
        let tabRadius: CGFloat = 10
        let bodyTop = rect.minY + tabHeight
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + tabRadius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + tabRadius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + tabWidth, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX + tabWidth + slope, y: bodyTop),
            control1: CGPoint(x: rect.minX + tabWidth + slope / 2, y: rect.minY),
            control2: CGPoint(x: rect.minX + tabWidth + slope / 2, y: bodyTop)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: bodyTop))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: bodyTop + radius), control: CGPoint(x: rect.maxX, y: bodyTop))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct DocumentRow: View {
    let node: LibraryNode

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            if node.isFolder {
                Image(systemName: "folder")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 36)
                Text(node.name).font(.body)
                Spacer()
                Text("\(node.children.count) items")
                    .foregroundStyle(.secondary)
            } else {
                PreviewLoader(node: node) { preview in
                    HStack(spacing: Theme.Space.m) {
                        PageImage(image: preview?.image, isPlaceholder: node.isPlaceholder)
                            .frame(width: 28, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.hairline))
                        Text(node.name).font(.body).lineLimit(1)
                        Spacer()
                        Text(detailText(node, preview)).foregroundStyle(.secondary)
                    }
                }
            }
            Text(node.modified, format: .dateTime.day().month(.abbreviated).year())
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, Theme.Space.s)
        .padding(.horizontal, Theme.Space.s)
        .contentShape(Rectangle())
    }
}
