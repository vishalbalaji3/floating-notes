import Cocoa
import Combine
import ServiceManagement
import Sparkle
import SwiftUI

@MainActor
final class UpdateSettings: ObservableObject {
    @Published private(set) var automaticallyChecksForUpdates = false
    private let updater: SPUUpdater
    private var observation: AnyCancellable?

    init(updater: SPUUpdater) {
        self.updater = updater
        observation = updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updater.automaticallyChecksForUpdates = enabled
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateSettings: UpdateSettings
    let onChangeNotesDirectory: (URL) throws -> Void
    let onCheckForUpdates: () -> Void

    @State private var notesDirectory: URL
    @State private var errorMessage: String?
    @State private var errorTitle = "Couldn’t Change Notes Folder"

    init(
        settings: AppSettings,
        updateSettings: UpdateSettings,
        onChangeNotesDirectory: @escaping (URL) throws -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.settings = settings
        self.updateSettings = updateSettings
        self.onChangeNotesDirectory = onChangeNotesDirectory
        self.onCheckForUpdates = onCheckForUpdates
        _notesDirectory = State(initialValue: NotesRepository.shared.notesDirectory)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("General")
                        .font(.headline)
                    Toggle("Launch at login", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { enabled in
                            do {
                                try settings.setLaunchAtLogin(enabled)
                            } catch {
                                errorTitle = "Couldn’t Change Launch at Login"
                                errorMessage = error.localizedDescription
                            }
                        }
                    ))
                    if settings.loginItemStatus == .requiresApproval {
                        Text("Allow Floating Notes in System Settings to launch at login.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Login Items Settings…") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                    Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                    Toggle("Show Dock icon", isOn: $settings.showDockIcon)
                    Text("You can hide both icons. Floating Notes keeps running and remains available with \(HotKeyManager.displayString).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("App icon")
                        .font(.headline)
                    HStack(spacing: 12) {
                        ForEach(AppIconChoice.allCases) { icon in
                            appIconButton(icon)
                        }
                    }
                    Text("The selected icon is used in the Dock and app switcher. Monogram is the default for new installs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Updates")
                        .font(.headline)
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updateSettings.automaticallyChecksForUpdates },
                        set: { updateSettings.setAutomaticallyChecksForUpdates($0) }
                    ))
                    HStack {
                        Button("Check for Updates…", action: onCheckForUpdates)
                        Spacer()
                        Text("Version \(versionString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Checks run daily while Floating Notes is running. You choose when to install an available update.")
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
        }
        .frame(width: 520, height: 620)
        .onAppear { settings.refreshLoginItemStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.refreshLoginItemStatus()
        }
        .alert(
            errorTitle,
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

    private func appIconButton(_ icon: AppIconChoice) -> some View {
        let isSelected = settings.appIcon == icon

        return Button {
            settings.appIcon = icon
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let image = icon.image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(icon.displayName)
                        .fontWeight(.medium)
                    Text(icon.isDefault ? "Default" : "Alternate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use \(icon.displayName) app icon")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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
            errorTitle = "Couldn’t Change Notes Folder"
            errorMessage = error.localizedDescription
        }
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(
        settings: AppSettings,
        updater: SPUUpdater,
        onChangeNotesDirectory: @escaping (URL) throws -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Floating Notes Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 520, height: 620)
        window.center()
        window.setFrameAutosaveName("FloatingNotesSettings")
        window.contentView = NSHostingView(
            rootView: SettingsView(
                settings: settings,
                updateSettings: UpdateSettings(updater: updater),
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
