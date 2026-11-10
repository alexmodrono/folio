import SwiftUI

final class HomeViewController: NSHostingController<HomeView> {
    init(model: HomeModel) {
        super.init(rootView: HomeView(model: model))
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

struct HomeView: View {
    @Bindable var model: HomeModel
    @Bindable private var store = LibraryStore.shared
    @State private var renaming: LibraryNode?
    @State private var newName = ""

    private var folder: LibraryNode {
        model.folderURL.flatMap(store.node(at:)) ?? store.root
    }

    private var isRoot: Bool { model.folderURL == nil }

    private var query: String { model.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var items: [LibraryNode] {
        let base: [LibraryNode]
        if isRoot, model.tab == .favorites {
            base = store.favoriteDocuments
        } else if query.isEmpty {
            base = folder.children
        } else {
            base = folder.allDocuments
        }
        return query.isEmpty ? base : base.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                let items = self.items
                if items.isEmpty {
                    emptyState
                } else if model.layout == .grid {
                    grid(items)
                } else {
                    list(items)
                }
            }
            .padding(.horizontal, Theme.Space.xxl)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(Theme.canvas)
        .dropDestination(for: URL.self) { urls, _ in
            guard !folder.isReadOnly else { return false }
            store.importFiles(urls, into: folder.url == store.rootURL ? nil : folder.url)
            return true
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let node = renaming { _ = try? store.rename(node.url, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            if isRoot {
                TabPill(title: "My documents", isSelected: model.tab == .all) { model.tab = .all }
                TabPill(title: "Favorites", isSelected: model.tab == .favorites) { model.tab = .favorites }
            }
            Spacer(minLength: Theme.Space.l)
            Menu {
                Picker("Sort By", selection: $store.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(store.sort.title, systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Picker("Layout", selection: $model.layout) {
                Label("Grid", systemImage: "square.grid.2x2").tag(HomeLayout.grid)
                Label("List", systemImage: "list.bullet").tag(HomeLayout.list)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .fixedSize()
        }
    }

    // MARK: Content

    private func grid(_ items: [LibraryNode]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Theme.gridMinimum, maximum: Theme.gridMaximum), spacing: Theme.Space.xl, alignment: .top)],
            alignment: .leading,
            spacing: Theme.Space.xl
        ) {
            ForEach(items) { node in
                Button { model.open(node.url) } label: {
                    if node.isFolder { FolderCard(node: node) } else { DocumentCard(node: node) }
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(node.name)
                .contextMenu { menu(for: node) }
            }
        }
    }

    private func list(_ items: [LibraryNode]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { node in
                Button { model.open(node.url) } label: { DocumentRow(node: node) }
                    .buttonStyle(.plain)
                    .contextMenu { menu(for: node) }
                Divider()
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Group {
            if !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if isRoot, model.tab == .favorites {
                ContentUnavailableView(
                    "No favorites",
                    systemImage: "star",
                    description: Text("Right-click a document and choose Add to Favorites.")
                )
            } else {
                ContentUnavailableView {
                    Label(isRoot ? "No PDFs yet" : "This folder is empty", systemImage: "doc")
                } description: {
                    if !folder.isReadOnly { Text("Drop PDFs here, or import them.") }
                } actions: {
                    if !folder.isReadOnly { Button("Import PDFs…") { model.importDocuments() } }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    @ViewBuilder
    private func menu(for node: LibraryNode) -> some View {
        Button("Open") { model.open(node.url) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
        if !node.isFolder {
            Button(store.isFavorite(node.url) ? "Remove from Favorites" : "Add to Favorites") {
                store.toggleFavorite(node.url)
            }
        }
        if node.isReadOnly {
            let placeholders = node.isFolder ? node.allDocuments.filter(\.isPlaceholder) : node.isPlaceholder ? [node] : []
            if !placeholders.isEmpty || !node.isFolder { Divider() }
            if !placeholders.isEmpty {
                Button("Download") { store.download(placeholders.map(\.url)) }
            }
            if !node.isFolder {
                Button("Copy to My Documents") { store.copyToLibrary([node.url], into: nil) }
            }
        } else {
            readWriteItems(for: node)
        }
    }

    @ViewBuilder
    private func readWriteItems(for node: LibraryNode) -> some View {
        Button("Rename…") {
            newName = node.name
            renaming = node
        }
        Divider()
        Button("Move to Trash", role: .destructive) { store.trash([node.url]) }
    }
}

private struct TabPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.tab)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Theme.pillRadius, style: .continuous).fill(.quaternary)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A slight press scale, no hover motion.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
