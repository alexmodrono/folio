import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let host = NSHostingController(rootView: SettingsView())
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        self.init(window: window)
    }
}

struct SettingsView: View {
    @AppStorage("autoAttach") private var autoAttach = true
    @State private var libraryPath = LibraryStore.shared.rootURL.path
    @State private var confirmingSignOut = false
    @State private var importingSignIn = false
    @Bindable private var findle = Findle.shared

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Folder") {
                    HStack(spacing: Theme.Space.s) {
                        Text((libraryPath as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…", action: chooseFolder)
                    }
                }
            }
            Section("Moodle") {
                switch findle.status {
                case .connected(let url):
                    LabeledContent("Courses") {
                        HStack(spacing: Theme.Space.s) {
                            Text((url.path as NSString).abbreviatingWithTildeInPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Button("Change…", action: chooseMoodleFolder)
                        }
                    }
                case .notSetUp:
                    LabeledContent("Courses") {
                        HStack(spacing: Theme.Space.s) {
                            Text("Not set up").foregroundStyle(.secondary)
                            Button("Open Findle") { findle.openApp() }
                        }
                    }
                case .notInstalled:
                    LabeledContent("Courses") {
                        HStack(spacing: Theme.Space.s) {
                            Text("Needs Findle").foregroundStyle(.secondary)
                            Button("Get Findle") { findle.getApp() }
                        }
                    }
                }
                Toggle("Show in sidebar", isOn: Binding(get: { findle.isShown }, set: { findle.setShown($0) }))
            }
            Section("ChatGPT") {
                Toggle("Attach the open PDF to new chats", isOn: $autoAttach)
                Button("Import Sign-In from a Browser…") { importingSignIn = true }
                Button("Sign Out of ChatGPT…") { confirmingSignOut = true }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
        .sheet(isPresented: $importingSignIn) {
            SessionImportView(model: SessionImportModel(), style: .sheet) { _ in importingSignIn = false }
        }
        .onAppear { findle.refresh() }
        .confirmationDialog("Sign out of ChatGPT?", isPresented: $confirmingSignOut) {
            Button("Sign Out", role: .destructive) {
                Task { await ChatGPTSession.signOut() }
            }
        } message: {
            Text("This removes the ChatGPT session saved in Folio.")
        }
    }

    private func chooseMoodleFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use Folder"
        panel.directoryURL = findle.folderURL ?? Findle.cloudStorage
        guard panel.runModal() == .OK, let url = panel.url else { return }
        findle.choose(url)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.directoryURL = LibraryStore.shared.rootURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        LibraryStore.shared.setRoot(url)
        libraryPath = url.path
    }
}
