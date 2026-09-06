import SwiftUI

struct NoteEditorView: View {
    @ObservedObject var store: NotesStore
    var onOpenFolder: () -> Void
    var onOpenSettings: () -> Void
    var onHide: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var isShowingSwitcher = false
    @State private var isShowingActionPanel = false
    @State private var isShowingFormatBar = false
    @State private var isShowingTrashConfirm = false
    @State private var pendingInsertion: PendingMarkdownInsertion?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                PlainTextEditor(
                    text: Binding(get: { store.source }, set: store.updateSource),
                    pendingInsertion: $pendingInsertion,
                    identity: store.editorIdentity,
                    initialCursorPosition: store.cursorPosition,
                    onCursorChange: store.updateCursor,
                    onShowActions: toggleActionPanel,
                    onShowSettings: onOpenSettings
                )
                bottomBar
            }
            .frame(minWidth: 360, minHeight: 240)
            .background(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.97))

            if isShowingSwitcher || isShowingActionPanel {
                Color.black.opacity(0.08)
                    .onTapGesture {
                        isShowingSwitcher = false
                        isShowingActionPanel = false
                    }
                    .transition(.opacity)
            }
            if isShowingSwitcher {
                NoteSwitcherView(store: store, isPresented: $isShowingSwitcher)
                    .padding(.horizontal, 28)
                    .padding(.top, 88)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }
            if isShowingActionPanel {
                ActionPanelView(isPresented: $isShowingActionPanel, actions: editorActions)
                    .padding(.horizontal, 28)
                    .padding(.top, 88)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }

            hiddenShortcuts
        }
        .ignoresSafeArea(.container, edges: .top)
        .animation(.easeOut(duration: 0.15), value: isShowingSwitcher)
        .animation(.easeOut(duration: 0.15), value: isShowingActionPanel)
        .animation(.easeOut(duration: 0.15), value: isShowingFormatBar)
        .confirmationDialog(
            "Move \"\(store.activeTitle)\" to Trash?",
            isPresented: $isShowingTrashConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let id = store.activeID { store.trash(id) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onExitCommand {
            if isShowingSwitcher || isShowingActionPanel {
                isShowingSwitcher = false
                isShowingActionPanel = false
            } else {
                onHide()
            }
        }
    }

    private var header: some View {
        ZStack {
            Text(store.activeTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 100)
                .help(store.activeTitle)
            HStack {
                HeaderWindowControls()
                    .frame(width: 60, height: 14)
                Spacer()
                actionPill
            }
            .padding(.leading, 19)
            .padding(.trailing, 8)
        }
        .frame(height: 52)
    }

    private var actionPill: some View {
        HStack(spacing: 8) {
            Button { toggleActionPanel() } label: { Image(systemName: "command").frame(width: 20, height: 20) }
                .help("Search Actions (⌘K)")
                .accessibilityLabel("Search Actions")
            Button { toggleSwitcher() } label: { Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled").frame(width: 20, height: 20) }
                .help("Browse Notes (⌘P)")
                .accessibilityLabel("Browse Notes")
            Button { store.createNote() } label: { Image(systemName: "plus").frame(width: 20, height: 20) }
                .help("New Note (⌘N)")
                .accessibilityLabel("New Note")
        }
        .buttonStyle(.plain)
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.black.opacity(0.18), in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.10)))
    }

    /// Keyboard shortcuts for actions that no longer have a visible header button — they live in
    /// the ⌘K action panel instead, but the shortcuts still work directly.
    private var hiddenShortcuts: some View {
        Group {
            Button("") { toggleActionPanel() }
                .keyboardShortcut("k", modifiers: .command)
            Button("", action: onOpenSettings)
                .keyboardShortcut(",", modifiers: .command)
            Button("") { toggleSwitcher() }
                .keyboardShortcut("p", modifiers: .command)
            Button("") { store.createNote() }
                .keyboardShortcut("n", modifiers: .command)
            Button("", action: onOpenFolder)
                .keyboardShortcut("o", modifiers: .command)
            Button("", role: .destructive) { isShowingTrashConfirm = true }
                .keyboardShortcut(.delete, modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    private var editorActions: [EditorAction] {
        [
            EditorAction(systemImage: "plus", title: "New Note", shortcut: ["⌘", "N"]) {
                store.createNote()
            },
            EditorAction(systemImage: "rectangle.portrait.on.rectangle.portrait.angled", title: "Browse Notes", shortcut: ["⌘", "P"]) {
                toggleSwitcher()
            },
            EditorAction(systemImage: "folder", title: "Reveal Notes Folder", shortcut: ["⌘", "O"], perform: onOpenFolder),
            EditorAction(systemImage: "gearshape", title: "Settings", shortcut: ["⌘", ","], perform: onOpenSettings),
            EditorAction(systemImage: "trash", title: "Move to Trash", shortcut: ["⌘", "⌫"], isEnabled: store.activeID != nil) {
                isShowingTrashConfirm = true
            },
        ]
    }

    private func toggleActionPanel() {
        if isShowingActionPanel {
            isShowingActionPanel = false
        } else {
            isShowingActionPanel = true
            isShowingSwitcher = false
        }
    }

    private func toggleSwitcher() {
        if isShowingSwitcher {
            isShowingSwitcher = false
        } else {
            isShowingSwitcher = true
            isShowingActionPanel = false
        }
    }

    private var bottomBar: some View {
        ZStack {
            if isShowingFormatBar {
                FormattingToolbar { insertion in
                    pendingInsertion = PendingMarkdownInsertion(action: insertion)
                }
                .padding(.horizontal, 44)
                .transition(.opacity)
            } else {
                Text("\(store.source.count) characters")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            HStack {
                Spacer()
                Button {
                    isShowingFormatBar.toggle()
                } label: {
                    Group {
                        if isShowingFormatBar {
                            Image(systemName: "xmark.circle.fill")
                        } else {
                            Text("T").font(.system(size: 17, weight: .semibold, design: .serif))
                        }
                    }
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.18), in: Circle())
                    .overlay(Circle().strokeBorder(.primary.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help(isShowingFormatBar ? "Hide Formatting" : "Text Formatting")
                .accessibilityLabel(isShowingFormatBar ? "Hide Formatting" : "Text Formatting")
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

/// These are independent standard AppKit buttons, not the title bar's managed instances.
/// AppKit rewrites the frames of its own buttons during resizing even after reparenting.
private struct HeaderWindowControls: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowControlsView { WindowControlsView() }
    func updateNSView(_ nsView: WindowControlsView, context: Context) {}

    final class WindowControlsView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            subviews.forEach { $0.removeFromSuperview() }
            let controls: [(NSWindow.ButtonType, Selector, Bool)] = [
                (.closeButton, #selector(NSWindow.performClose(_:)), window.styleMask.contains(.closable)),
                (.miniaturizeButton, #selector(NSWindow.performMiniaturize(_:)), window.styleMask.contains(.miniaturizable)),
                (.zoomButton, #selector(NSWindow.performZoom(_:)), window.styleMask.contains(.resizable)),
            ]
            for (kind, action, enabled) in controls {
                guard let button = NSWindow.standardWindowButton(kind, for: window.styleMask) else { continue }
                button.target = window
                button.action = action
                button.isEnabled = enabled
                button.autoresizingMask = []
                addSubview(button)
            }
            needsLayout = true
        }

        override func layout() {
            super.layout()
            for (index, button) in subviews.enumerated() {
                button.setFrameOrigin(NSPoint(x: CGFloat(index) * 23, y: (bounds.height - button.frame.height) / 2))
            }
        }
    }
}
