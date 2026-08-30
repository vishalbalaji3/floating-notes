import Cocoa
import SwiftUI

/// A non-activating floating panel: it never becomes the key/main app, sits above other
/// windows, stays visible across Spaces, and treats Escape as "hide" instead of "close".
final class NotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class NotesWindowController: NSWindowController {
    private let store: NotesStore

    init(store: NotesStore, onOpenSettings: @escaping () -> Void) {
        self.store = store
        let panel = NotesPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.setFrameAutosaveName("FloatingNotesPanel")

        super.init(window: panel)

        let content = NoteEditorView(
            store: store,
            onOpenFolder: { [weak self] in self?.revealFolder() },
            onOpenSettings: onOpenSettings,
            onHide: { [weak self] in self?.hide() }
        )
        panel.contentView = NSHostingView(rootView: content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggle() {
        guard let window else { return }
        if window.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        store.reload()
        NSApp.unhide(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        store.flush()
        window?.orderOut(nil)
    }

    private func revealFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([NotesRepository.shared.notesDirectory])
    }
}
