import AppKit

enum AppIconChoice: String, CaseIterable, Identifiable {
    case monogram
    case notes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monogram: "Monogram"
        case .notes: "Notes"
        }
    }

    var isDefault: Bool { self == .monogram }

    private var resourceName: String {
        switch self {
        case .monogram: "AppIcon"
        case .notes: "AppIconNotes"
        }
    }

    var image: NSImage? {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
