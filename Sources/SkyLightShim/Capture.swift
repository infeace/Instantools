import CoreGraphics

extension SkyLight {
    private typealias WindowListCreateImage =
        @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?

    /// `CGWindowListCreateImage` is obsoleted in the macOS 15 SDK but still exported. Capturing one's own
    /// windows needs no Screen Recording permission, which is all Settings snapshots use it for.
    private static let windowListCreateImage = symbol("CGWindowListCreateImage", as: WindowListCreateImage.self)

    public static func captureOwnWindow(_ windowId: CGWindowID) -> CGImage? {
        windowListCreateImage?(.null, .optionIncludingWindow, windowId, [.boundsIgnoreFraming, .bestResolution])?
            .takeRetainedValue()
    }
}
