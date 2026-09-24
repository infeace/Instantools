import CoreFoundation

extension SkyLight {
    private typealias CoreDockSendNotification = @convention(c) (CFString, Int32) -> Void

    private static let coreDockSendNotification = symbol("CoreDockSendNotification", as: CoreDockSendNotification.self)

    /// App Exposé for the frontmost app, as the Dock shows it. False when the call is missing, and then
    /// the switch simply happens without it.
    @discardableResult
    public static func showAppExpose() -> Bool {
        guard let coreDockSendNotification else { return false }
        coreDockSendNotification("com.apple.expose.front.awake" as CFString, 0)
        return true
    }
}
