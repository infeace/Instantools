import Foundation

/// Carries "Settings was open" from a copy of InstantTab that is being replaced (by the login agent,
/// or by a fresh copy when the agent is turned off) to its replacement, so the swap goes unnoticed.
enum Handoff {
    private static let key = "reopenSettingsAt"
    private static let window: TimeInterval = 15

    static func markSettingsOpen() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        UserDefaults.standard.synchronize()
    }

    /// True once if a replaced copy had Settings open a moment ago.
    static func consumeSettingsOpen() -> Bool {
        let marked = UserDefaults.standard.double(forKey: key)
        guard marked > 0 else { return false }
        UserDefaults.standard.removeObject(forKey: key)
        return Date().timeIntervalSince1970 - marked < window
    }
}
