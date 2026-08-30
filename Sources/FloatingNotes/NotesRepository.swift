import Foundation

struct NoteSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let modifiedAt: Date
}

final class NotesRepository {
    static let shared = NotesRepository()
    static let notesDirectoryDefaultsKey = "notesDirectory"
    static let maximumDerivedTitleLength = 60

    static var defaultNotesDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Floating Notes", isDirectory: true)
    }

    private(set) var notesDirectory: URL

    private init() {
        if let storedPath = UserDefaults.standard.string(forKey: Self.notesDirectoryDefaultsKey) {
            notesDirectory = URL(fileURLWithPath: storedPath, isDirectory: true).standardizedFileURL
        } else {
            notesDirectory = Self.defaultNotesDirectory
        }
        try? FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
    }

    func setNotesDirectory(_ directory: URL) throws {
        let resolved = directory.standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw CocoaError(.fileWriteFileExists)
            }
        } else {
            try FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
        }
        notesDirectory = resolved
        UserDefaults.standard.set(resolved.path, forKey: Self.notesDirectoryDefaultsKey)
    }

    func fileURL(for id: String) -> URL {
        notesDirectory.appendingPathComponent(id)
    }

    func list() -> [NoteSummary] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: notesDirectory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )) ?? []

        let summaries: [NoteSummary] = contents.compactMap { url in
            guard url.pathExtension.lowercased() == "md" else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { return nil }
            return NoteSummary(
                id: url.lastPathComponent,
                title: url.deletingPathExtension().lastPathComponent,
                modifiedAt: values?.contentModificationDate ?? .distantPast
            )
        }

        return summaries.sorted { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    func create() -> NoteSummary {
        let title = uniqueTitle(desired: "Untitled", excluding: nil)
        let id = "\(title).md"
        FileManager.default.createFile(atPath: fileURL(for: id).path, contents: Data())
        return NoteSummary(id: id, title: title, modifiedAt: Date())
    }

    func read(_ id: String) -> String {
        (try? String(contentsOf: fileURL(for: id), encoding: .utf8)) ?? ""
    }

    func write(_ id: String, source: String) {
        try? source.write(to: fileURL(for: id), atomically: true, encoding: .utf8)
    }

    /// Note titles are content, not separate metadata. Use the first non-empty line, remove the
    /// most common Markdown presentation markers, and cap it to a Finder-friendly length.
    func derivedTitle(from source: String) -> String {
        guard var title = source
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return "Untitled"
        }

        title = title.replacingOccurrences(
            of: #"^(?:#{1,6}|>|[-+*]|\d+\.)\s+"#,
            with: "",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: #"^\[[ xX]\]\s*"#,
            with: "",
            options: .regularExpression
        )

        if let linkRange = title.range(of: #"^\[([^]]+)\]\([^)]+\)$"#, options: .regularExpression) {
            let link = String(title[linkRange])
            if let closeBracket = link.firstIndex(of: "]") {
                title = String(link[link.index(after: link.startIndex)..<closeBracket])
            }
        }

        for marker in ["<u>", "</u>", "**", "__", "~~", "`", "*", "_"] {
            title = title.replacingOccurrences(of: marker, with: "")
        }
        title = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        title = sanitize(String(title.prefix(Self.maximumDerivedTitleLength)))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return title.isEmpty ? "Untitled" : title
    }

    /// Only an exact filename match is a no-op; a case/diacritic-only change still renames.
    func rename(id: String, to rawTitle: String) -> String {
        let currentTitle = (id as NSString).deletingPathExtension
        let desired = sanitize(rawTitle)
        guard !desired.isEmpty, desired != currentTitle else { return id }
        let newTitle = uniqueTitle(desired: desired, excluding: id)
        let newID = "\(newTitle).md"
        do {
            try FileManager.default.moveItem(at: fileURL(for: id), to: fileURL(for: newID))
            return newID
        } catch {
            return id
        }
    }

    func trash(_ id: String) {
        try? FileManager.default.trashItem(at: fileURL(for: id), resultingItemURL: nil)
    }

    func search(_ query: String, in summaries: [NoteSummary]) -> [NoteSummary] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return summaries }
        return summaries.filter { summary in
            if summary.title.lowercased().contains(needle) { return true }
            return read(summary.id).lowercased().contains(needle)
        }
    }

    private func sanitize(_ title: String) -> String {
        title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    private func uniqueTitle(desired: String, excluding excludedID: String?) -> String {
        let existing = list().filter { $0.id != excludedID }.map { normalized($0.title) }
        var candidate = desired
        var suffix = 1
        while existing.contains(normalized(candidate)) {
            suffix += 1
            candidate = "\(desired) \(suffix)"
        }
        return candidate
    }
}
