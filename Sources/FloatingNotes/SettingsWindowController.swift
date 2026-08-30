import Cocoa
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onChangeNotesDirectory: (URL) throws -> Void
    let onCheckForUpdates: () -> Void

    @State private var notesDirectory: URL
    @State private var errorMessage: String?

    init(
        settings: AppSettings,
        onChangeNotesDirectory: @escaping (URL) throws -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.settings = settings
        self.onChangeNotesDirectory = onChangeNotesDirectory
        self.onCheckForUpdates = onCheckForUpdates
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
                Text("Updates")
                    .font(.headline)
                HStack {
                    Button("Check for Updates…", action: onCheckForUpdates)
                    Spacer()
                    Text("Version \(versionString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("When an update is available, you can review its release notes and install it immediately.")
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

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
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

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(
        settings: AppSettings,
        onChangeNotesDirectory: @escaping (URL) throws -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 445),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Floating Notes Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 520, height: 445)
        window.center()
        window.setFrameAutosaveName("FloatingNotesSettings")
        window.contentView = NSHostingView(
            rootView: SettingsView(
                settings: settings,
                onChangeNotesDirectory: onChangeNotesDirectory,
                onCheckForUpdates: onCheckForUpdates
            )
        )
        super.init(window: window)
        window.delegate = self
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

    func windowWillClose(_ notification: Notification) {
        // AppKit sends windowWillClose before isVisible changes. Defer the activation-policy
        // update so a hidden-Dock preference can return the app to accessory mode correctly.
        DispatchQueue.main.async { [onClose] in
            onClose()
        }
    }
}
