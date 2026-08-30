import SwiftUI

struct EditorAction: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let shortcut: [String]
    var isEnabled: Bool = true
    let perform: () -> Void
}

/// The ⌘K action palette. Only lists actions this app actually implements elsewhere
/// (new note, browse, reveal folder, trash) — no stubbed-out placeholders.
struct ActionPanelView: View {
    @Binding var isPresented: Bool
    let actions: [EditorAction]

    @State private var query = ""
    @State private var selection = 0

    private var filtered: [EditorAction] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return actions }
        return actions.filter { $0.title.lowercased().contains(needle) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(
                text: $query,
                placeholder: "Search for actions…",
                font: .systemFont(ofSize: 14),
                onMoveUp: { moveSelection(-1) },
                onMoveDown: { moveSelection(1) },
                onSubmit: activateSelection,
                onCancel: { isPresented = false }
            )
            .padding(12)
            Divider()
            if filtered.isEmpty {
                Text("No Actions")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, action in
                        row(action, isSelected: index == selection)
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .onChange(of: query) { _ in selection = 0 }
    }

    private func row(_ action: EditorAction, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.systemImage)
                .frame(width: 16)
            Text(action.title)
            Spacer()
            HStack(spacing: 4) {
                ForEach(action.shortcut, id: \.self) { KeyCap($0) }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(action.isEnabled ? .primary : .tertiary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { activate(action) }
    }

    private func moveSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        selection = (selection + delta + filtered.count) % filtered.count
    }

    private func activateSelection() {
        guard filtered.indices.contains(selection) else { return }
        activate(filtered[selection])
    }

    private func activate(_ action: EditorAction) {
        guard action.isEnabled else { return }
        isPresented = false
        action.perform()
    }
}

/// A small rounded keycap, e.g. for rendering "⌘" "K" as separate badges.
struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}
