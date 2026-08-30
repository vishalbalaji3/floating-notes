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

    /// Matches the preferred placement captured on a 1728 × 1084 visible screen:
    /// a 67-point gap from the right and a center 52.7% up the usable display area.
    private static let defaultRightInsetFraction: CGFloat = 67.0 / 1728.0
    private static let defaultVerticalCenterFraction: CGFloat = 0.527

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
        positionOnRight(panel)
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

    private func positionOnRight(_ window: NSWindow) {
        guard let screen = preferredScreen(for: window) else { return }
        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let rightInset = visibleFrame.width * Self.defaultRightInsetFraction
        let preferredOrigin = NSPoint(
            x: visibleFrame.maxX - windowSize.width - rightInset,
            y: visibleFrame.minY
                + visibleFrame.height * Self.defaultVerticalCenterFraction
                - windowSize.height / 2
        )

        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - windowSize.height)
        window.setFrameOrigin(NSPoint(
            x: min(max(preferredOrigin.x, visibleFrame.minX), maximumX),
            y: min(max(preferredOrigin.y, visibleFrame.minY), maximumY)
        ))
    }

    private func preferredScreen(for window: NSWindow) -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? window.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func revealFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([NotesRepository.shared.notesDirectory])
    }
}
