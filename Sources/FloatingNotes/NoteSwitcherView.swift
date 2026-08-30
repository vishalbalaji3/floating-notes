import SwiftUI

struct NoteSwitcherView: View {
    @ObservedObject var store: NotesStore
    @Binding var isPresented: Bool

    @State private var selection = 0
    @State private var pendingTrash: NoteSummary?

    var body: some View {
        VStack(spacing: 0) {
            SearchField(
                text: $store.searchQuery,
                placeholder: "Search for notes…",
                font: .systemFont(ofSize: 14),
                onMoveUp: { moveSelection(-1) },
                onMoveDown: { moveSelection(1) },
                onSubmit: activateSelection,
                onCancel: { isPresented = false }
            )
            .padding(12)
            Divider()
            if store.searchResults.isEmpty {
                Text(store.summaries.isEmpty ? "No Notes Yet" : "No Matches")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    ForEach(Array(store.searchResults.enumerated()), id: \.element.id) { index, note in
                        row(for: note, isSelected: index == selection)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
        }
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .confirmationDialog(
            "Move to Trash?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let note = pendingTrash { store.trash(note.id) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: store.searchQuery) { _ in selection = 0 }
    }

    private func row(for note: NoteSummary, isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 13))
                metadataLine(for: note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                pendingTrash = note
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .opacity(isSelected ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            store.load(note.id)
            isPresented = false
        }
        .contextMenu {
            Button("Move to Trash", role: .destructive) {
                pendingTrash = note
            }
        }
    }

    private func metadataLine(for note: NoteSummary) -> some View {
        HStack(spacing: 4) {
            if note.id == store.activeID {
                Circle().fill(.blue).frame(width: 5, height: 5)
                Text("Current")
            } else {
                Text(note.modifiedAt, style: .relative)
            }
            Text("•")
            Text("\(characterCount(for: note)) characters")
        }
    }

    private func characterCount(for note: NoteSummary) -> Int {
        note.id == store.activeID ? store.source.count : NotesRepository.shared.read(note.id).count
    }

    private func moveSelection(_ delta: Int) {
        guard !store.searchResults.isEmpty else { return }
        selection = (selection + delta + store.searchResults.count) % store.searchResults.count
    }

    private func activateSelection() {
        guard store.searchResults.indices.contains(selection) else { return }
        store.load(store.searchResults[selection].id)
        isPresented = false
    }
}
