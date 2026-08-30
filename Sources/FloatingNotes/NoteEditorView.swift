import SwiftUI

struct NoteEditorView: View {
    @ObservedObject var store: NotesStore
    var onOpenFolder: () -> Void
    var onOpenSettings: () -> Void
    var onHide: () -> Void

    @State private var isShowingSwitcher = false
    @State private var isShowingActionPanel = false
    @State private var isShowingFormatBar = false
    @State private var isShowingTrashConfirm = false
    @State private var pendingInsertion: PendingMarkdownInsertion?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider()
                PlainTextEditor(
                    text: Binding(get: { store.source }, set: store.updateSource),
                    pendingInsertion: $pendingInsertion,
                    initialCursorPosition: store.cursorPosition,
                    onCursorChange: store.updateCursor,
                    onShowActions: toggleActionPanel,
                    onShowSettings: onOpenSettings
                )
                .id(store.editorIdentity)
                Divider()
                if isShowingFormatBar {
                    formattingBar
                } else {
                    footer
                }
            }
            .frame(minWidth: 360, minHeight: 240)
            .background(.regularMaterial)
            .overlay(alignment: .bottomTrailing) {
                if !isShowingFormatBar {
                    formatToggleButton.padding(12)
                }
            }

            if isShowingSwitcher || isShowingActionPanel {
                Color.black.opacity(0.35)
                    .onTapGesture {
                        isShowingSwitcher = false
                        isShowingActionPanel = false
                    }
                    .transition(.opacity)
            }
            if isShowingSwitcher {
                NoteSwitcherView(store: store, isPresented: $isShowingSwitcher)
                    .padding(.top, 44)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }
            if isShowingActionPanel {
                ActionPanelView(isPresented: $isShowingActionPanel, actions: editorActions)
                    .padding(.top, 44)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }

            hiddenShortcuts
        }
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
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            HStack {
                Spacer()
                actionPill
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var actionPill: some View {
        HStack(spacing: 14) {
            Button { toggleActionPanel() } label: { Image(systemName: "command") }
            Button { openSwitcher() } label: { Image(systemName: "square.on.square") }
            Button { store.createNote() } label: { Image(systemName: "plus") }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }

    /// Keyboard shortcuts for actions that no longer have a visible header button — they live in
    /// the ⌘K action panel instead, but the shortcuts still work directly.
    private var hiddenShortcuts: some View {
        Group {
            Button("") { toggleActionPanel() }
                .keyboardShortcut("k", modifiers: .command)
            Button("", action: onOpenSettings)
                .keyboardShortcut(",", modifiers: .command)
            Button("") { openSwitcher() }
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
            EditorAction(systemImage: "square.on.square", title: "Browse Notes", shortcut: ["⌘", "P"]) {
                openSwitcher()
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

    private func openSwitcher() {
        isShowingSwitcher = true
        isShowingActionPanel = false
    }

    private var formatToggleButton: some View {
        Button {
            isShowingFormatBar = true
        } label: {
            Text("T")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var formattingBar: some View {
        HStack(spacing: 8) {
            FormattingToolbar { insertion in
                pendingInsertion = PendingMarkdownInsertion(action: insertion)
            }
            Spacer()
            Button {
                isShowingFormatBar = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .transition(.opacity)
    }

    private var footer: some View {
        Text("\(store.source.count) characters")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}
