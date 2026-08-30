import Cocoa
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private var notesController: NotesWindowController!
    private var settingsController: SettingsWindowController!
    private var store: NotesStore!
    private let settings = AppSettings.shared
    private var applicationToReactivate: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = NotesStore()
        settingsController = SettingsWindowController(
            settings: settings,
            onChangeNotesDirectory: { [weak self] url in
                try self?.store.changeNotesDirectory(to: url)
            },
            onCheckForUpdates: { [weak self] in
                self?.updaterController.checkForUpdates(nil)
            },
            onClose: { [weak self] in
                self?.settingsDidClose()
            }
        )
        notesController = NotesWindowController(
            store: store,
            onOpenSettings: { [weak self] in self?.showSettings() }
        )

        installMainMenu()
        settings.onMenuBarIconChange = { [weak self] isVisible in
            self?.setMenuBarIconVisible(isVisible)
        }
        settings.onDockIconChange = { [weak self] _ in
            self?.updateActivationPolicy()
        }
        setMenuBarIconVisible(settings.showMenuBarIcon)
        updateActivationPolicy()

        hotKeyManager = HotKeyManager { [weak self] in
            self?.notesController.toggle()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        notesController.hide()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        notesController.show()
        return true
    }

    @objc private func showNotes() {
        notesController.show()
    }

    @objc private func toggleNotes() {
        notesController.toggle()
    }

    @objc private func createNote() {
        store.createNote()
        notesController.show()
    }

    @objc private func showSettings() {
        if settingsController.window?.isVisible != true,
           let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            applicationToReactivate = frontmostApplication
        }

        // Accessory apps do not present their main menu. Temporarily become a regular app while
        // Settings is open so every app-menu command remains available even when the Dock icon
        // preference is disabled.
        NSApp.setActivationPolicy(.regular)
        settingsController.show()
    }

    @objc private func revealFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([NotesRepository.shared.notesDirectory])
    }

    @objc private func quitToBackground() {
        notesController.hide()
        settingsController.close()
        NSApp.hide(nil)
    }

    @objc private func quitCompletely() {
        let alert = NSAlert()
        alert.messageText = "Quit Floating Notes Completely?"
        alert.informativeText = "The global shortcut and menu bar icon will stop working until you open Floating Notes again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit Completely")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSApp.terminate(nil)
    }

    private func updateActivationPolicy() {
        let settingsAreVisible = settingsController?.window?.isVisible == true
        NSApp.setActivationPolicy(settings.showDockIcon || settingsAreVisible ? .regular : .accessory)
    }

    private func settingsDidClose() {
        updateActivationPolicy()

        let application = applicationToReactivate
        applicationToReactivate = nil

        // Changing from a regular app back to an accessory app is asynchronous. Hand focus back
        // on the following run-loop turn so the previous app restores its key window as well as
        // its menu bar.
        DispatchQueue.main.async {
            guard let application, !application.isTerminated else {
                NSApp.deactivate()
                return
            }

            if #available(macOS 14.0, *) {
                NSApp.yieldActivation(to: application)
                application.activate(
                    from: NSRunningApplication.current,
                    options: [.activateAllWindows]
                )
            } else {
                NSApp.deactivate()
                application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
        }
    }

    private func setMenuBarIconVisible(_ isVisible: Bool) {
        if isVisible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Floating Notes")
            item.menu = makeStatusMenu()
            statusItem = item
        } else if !isVisible, let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Toggle Notes (\(HotKeyManager.displayString))", action: #selector(toggleNotes)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", action: #selector(showSettings)))
        menu.addItem(checkForUpdatesItem())
        menu.addItem(item("Reveal Notes Folder", action: #selector(revealFolder)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Floating Notes", action: #selector(quitToBackground), keyEquivalent: "q"))
        menu.addItem(item(
            "Quit Floating Notes Completely",
            action: #selector(quitCompletely),
            keyEquivalent: "q",
            modifiers: [.command, .shift]
        ))
        return menu
    }

    /// A native main menu is required for Cocoa text controls to receive standard editing
    /// commands such as copy, paste, undo, and select all.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Floating Notes", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(checkForUpdatesItem())
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", action: #selector(showSettings), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Floating Notes", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit Floating Notes", action: #selector(quitToBackground), keyEquivalent: "q"))
        appMenu.addItem(item(
            "Quit Floating Notes Completely",
            action: #selector(quitCompletely),
            keyEquivalent: "q",
            modifiers: [.command, .shift]
        ))
        let appRoot = NSMenuItem()
        appRoot.submenu = appMenu
        mainMenu.addItem(appRoot)

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("New Note", action: #selector(createNote), keyEquivalent: "n"))
        fileMenu.addItem(item("Show Floating Notes", action: #selector(showNotes)))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Reveal Notes Folder", action: #selector(revealFolder), keyEquivalent: "o"))
        let fileRoot = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileRoot.submenu = fileMenu
        mainMenu.addItem(fileRoot)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(responderItem("Undo", action: "undo:", keyEquivalent: "z"))
        editMenu.addItem(responderItem("Redo", action: "redo:", keyEquivalent: "z", modifiers: [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(responderItem("Cut", action: "cut:", keyEquivalent: "x"))
        editMenu.addItem(responderItem("Copy", action: "copy:", keyEquivalent: "c"))
        editMenu.addItem(responderItem("Paste", action: "paste:", keyEquivalent: "v"))
        editMenu.addItem(responderItem("Paste and Match Style", action: "pasteAsPlainText:", keyEquivalent: "v", modifiers: [.command, .option, .shift]))
        editMenu.addItem(responderItem("Delete", action: "delete:", keyEquivalent: ""))
        editMenu.addItem(.separator())
        editMenu.addItem(responderItem("Select All", action: "selectAll:", keyEquivalent: "a"))
        let editRoot = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editRoot.submenu = editMenu
        mainMenu.addItem(editRoot)

        let formatMenu = NSMenu(title: "Format")
        formatMenu.addItem(responderItem("Bold", action: "toggleMarkdownBold:", keyEquivalent: "b"))
        formatMenu.addItem(responderItem("Italic", action: "toggleMarkdownItalic:", keyEquivalent: "i"))
        formatMenu.addItem(responderItem("Underline", action: "toggleMarkdownUnderline:", keyEquivalent: "u"))
        formatMenu.addItem(responderItem("Strikethrough", action: "toggleMarkdownStrikethrough:", keyEquivalent: "x", modifiers: [.command, .shift]))
        formatMenu.addItem(.separator())
        formatMenu.addItem(responderItem("Link", action: "insertMarkdownLink:", keyEquivalent: "l"))
        formatMenu.addItem(responderItem("Inline Code", action: "toggleMarkdownInlineCode:", keyEquivalent: "e"))
        formatMenu.addItem(responderItem(
            "Code Block",
            action: "insertMarkdownCodeBlock:",
            keyEquivalent: "c",
            modifiers: [.command, .option]
        ))
        formatMenu.addItem(responderItem(
            "Block Quote",
            action: "toggleMarkdownBlockQuote:",
            keyEquivalent: "b",
            modifiers: [.command, .shift]
        ))
        let formatRoot = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        formatRoot.submenu = formatMenu
        mainMenu.addItem(formatRoot)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(item("Show Floating Notes", action: #selector(showNotes)))
        windowMenu.addItem(item("Settings", action: #selector(showSettings)))
        let windowRoot = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowRoot.submenu = windowMenu
        mainMenu.addItem(windowRoot)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func item(
        _ title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = self
        return menuItem
    }

    private func responderItem(
        _ title: String,
        action: String,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: Selector((action)), keyEquivalent: keyEquivalent)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = nil
        return menuItem
    }

    private func checkForUpdatesItem() -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        menuItem.target = updaterController
        return menuItem
    }
}
