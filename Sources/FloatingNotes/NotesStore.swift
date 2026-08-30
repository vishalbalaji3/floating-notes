import Foundation

@MainActor
final class NotesStore: ObservableObject {
    private static let activeIDDefaultsKey = "activeNoteID"
    private static let cursorPositionsDefaultsKey = "noteCursorPositions"
    private static let saveDebounceInterval: TimeInterval = 0.3

    @Published private(set) var summaries: [NoteSummary] = []
    @Published private(set) var activeID: String?
    @Published private(set) var source = ""
    @Published private(set) var cursorPosition = 0
    @Published private(set) var editorIdentity = UUID()
    @Published var searchQuery = "" {
        didSet { refreshSearchResults() }
    }
    @Published private(set) var searchResults: [NoteSummary] = []

    var activeTitle: String {
        repository.derivedTitle(from: source)
    }

    private let repository = NotesRepository.shared
    private var saveTimer: Timer?
    private var cursorPositions: [String: Int]

    init() {
        cursorPositions = (UserDefaults.standard.dictionary(forKey: Self.cursorPositionsDefaultsKey) as? [String: Int]) ?? [:]
        reload()
    }

    /// If there are no notes, lands directly in a fresh one instead of showing an empty state.
    func reload() {
        summaries = repository.list()
        if summaries.isEmpty {
            let note = repository.create()
            summaries = repository.list()
            load(note.id)
            refreshSearchResults()
            return
        }
        let stored = UserDefaults.standard.string(forKey: Self.activeIDDefaultsKey)
        let resolvedID = (stored.flatMap { id in summaries.contains { $0.id == id } ? id : nil }) ?? summaries[0].id
        load(resolvedID)
        refreshSearchResults()
    }

    func load(_ id: String) {
        guard id != activeID else { return }
        flush()
        activeID = id
        source = repository.read(id)
        cursorPosition = cursorPositions[id] ?? (source as NSString).length
        editorIdentity = UUID()
        UserDefaults.standard.set(id, forKey: Self.activeIDDefaultsKey)
    }

    /// Records where the cursor is so reopening a note resumes right where it was left.
    func updateCursor(_ position: Int) {
        guard let activeID else { return }
        cursorPosition = position
        cursorPositions[activeID] = position
        UserDefaults.standard.set(cursorPositions, forKey: Self.cursorPositionsDefaultsKey)
    }

    func updateSource(_ updated: String) {
        guard activeID != nil, updated != source else { return }
        source = updated
        scheduleSave()
    }

    func createNote() {
        flush()
        let note = repository.create()
        summaries = repository.list()
        load(note.id)
        refreshSearchResults()
    }

    func changeNotesDirectory(to directory: URL) throws {
        flush()
        try repository.setNotesDirectory(directory)
        activeID = nil
        source = ""
        cursorPosition = 0
        UserDefaults.standard.removeObject(forKey: Self.activeIDDefaultsKey)
        reload()
    }

    /// Trashes whichever note `id` refers to, active or not. Lands in a fresh note if that
    /// was the last one, per the same "never show an empty state" rule as `reload()`.
    func trash(_ id: String) {
        // Cancel rather than flush: a debounced write firing after the file is trashed would
        // resurrect it at the same path.
        if id == activeID {
            saveTimer?.invalidate()
            saveTimer = nil
        }
        repository.trash(id)
        cursorPositions.removeValue(forKey: id)
        UserDefaults.standard.set(cursorPositions, forKey: Self.cursorPositionsDefaultsKey)
        summaries = repository.list()
        if id == activeID {
            activeID = nil
            source = ""
            UserDefaults.standard.removeObject(forKey: Self.activeIDDefaultsKey)
            if let next = summaries.first {
                load(next.id)
            } else {
                let note = repository.create()
                summaries = repository.list()
                load(note.id)
            }
        }
        refreshSearchResults()
    }

    func flush() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard let activeID else { return }
        repository.write(activeID, source: source)
        let derivedTitle = repository.derivedTitle(from: source)
        let renamedID = repository.rename(id: activeID, to: derivedTitle)
        if renamedID != activeID {
            if let position = cursorPositions.removeValue(forKey: activeID) {
                cursorPositions[renamedID] = position
                UserDefaults.standard.set(cursorPositions, forKey: Self.cursorPositionsDefaultsKey)
            }
            self.activeID = renamedID
            UserDefaults.standard.set(renamedID, forKey: Self.activeIDDefaultsKey)
        }
        summaries = repository.list()
        refreshSearchResults()
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: Self.saveDebounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    private func refreshSearchResults() {
        searchResults = repository.search(searchQuery, in: summaries)
    }
}
