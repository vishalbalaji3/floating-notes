import Cocoa
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onChangeNotesDirectory: (URL) throws -> Void

    @State private var notesDirectory: URL
    @State private var errorMessage: String?

    init(settings: AppSettings, onChangeNotesDirectory: @escaping (URL) throws -> Void) {
        self.settings = settings
        self.onChangeNotesDirectory = onChangeNotesDirectory
        _notesDirectory = State(initialValue: NotesRepository.shared.notesDirectory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("General")
                    .font(.headline)
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                Toggle("Show Dock icon", isOn: $settings.showDockIcon)
                Text("You can hide both icons. Floating Notes keeps running and remains available with \(HotKeyManager.displayString).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Notes folder")
                    .font(.headline)
                Text(notesDirectory.path)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                HStack {
                    Button("Choose…", action: chooseDirectory)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([notesDirectory])
                    }
                    Spacer()
                    if notesDirectory.standardizedFileURL != NotesRepository.defaultNotesDirectory.standardizedFileURL {
                        Button("Use Default") {
                            changeDirectory(to: NotesRepository.defaultNotesDirectory)
                        }
                    }
                }

                Text("Changing folders does not move existing files. Filenames come from the first non-empty line, up to \(NotesRepository.maximumDerivedTitleLength) characters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 520)
        .alert(
            "Couldn’t Change Notes Folder",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Notes Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = notesDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        changeDirectory(to: url)
    }

    private func changeDirectory(to url: URL) {
        do {
            try onChangeNotesDirectory(url)
            notesDirectory = url.standardizedFileURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings, onChangeNotesDirectory: @escaping (URL) throws -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Floating Notes Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("FloatingNotesSettings")
        window.contentView = NSHostingView(
            rootView: SettingsView(settings: settings, onChangeNotesDirectory: onChangeNotesDirectory)
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
