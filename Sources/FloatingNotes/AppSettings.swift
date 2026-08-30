import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let showMenuBarIconKey = "showMenuBarIcon"
    static let showDockIconKey = "showDockIcon"

    @Published var showMenuBarIcon: Bool {
        didSet {
            UserDefaults.standard.set(showMenuBarIcon, forKey: Self.showMenuBarIconKey)
            onMenuBarIconChange?(showMenuBarIcon)
        }
    }

    @Published var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: Self.showDockIconKey)
            onDockIconChange?(showDockIcon)
        }
    }

    var onMenuBarIconChange: ((Bool) -> Void)?
    var onDockIconChange: ((Bool) -> Void)?

    private init() {
        if UserDefaults.standard.object(forKey: Self.showMenuBarIconKey) == nil {
            showMenuBarIcon = true
        } else {
            showMenuBarIcon = UserDefaults.standard.bool(forKey: Self.showMenuBarIconKey)
        }
        if UserDefaults.standard.object(forKey: Self.showDockIconKey) == nil {
            showDockIcon = true
        } else {
            showDockIcon = UserDefaults.standard.bool(forKey: Self.showDockIconKey)
        }
    }
}
