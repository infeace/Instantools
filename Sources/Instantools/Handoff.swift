import Foundation

/// Tells the copy that replaces this one (a reinstall, or the login agent's copy) to reopen Settings.
enum Handoff {
    private static let key = "reopenSettingsAt"
    private static let window: TimeInterval = 15

    static func markSettingsOpen() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        // Called just before exit(0), which would otherwise lose the write.
        UserDefaults.standard.synchronize()
    }

    static func consumeSettingsOpen() -> Bool {
        let marked = UserDefaults.standard.double(forKey: key)
        guard marked > 0 else { return false }
        UserDefaults.standard.removeObject(forKey: key)
        return Date().timeIntervalSince1970 - marked < window
    }
}
