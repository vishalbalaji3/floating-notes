import Cocoa

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let defaults = UserDefaults.standard
    let showDockIcon = defaults.object(forKey: AppSettings.showDockIconKey) == nil
        || defaults.bool(forKey: AppSettings.showDockIconKey)
    app.setActivationPolicy(showDockIcon ? .regular : .accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    // NSApplication's delegate reference is weak. Keep our programmatic delegate alive for the
    // entire event loop so menu actions, settings, saving, and the global hotkey remain wired.
    withExtendedLifetime(delegate) {
        app.run()
    }
}
