import CoreGraphics

extension SkyLight {
    private typealias WindowListCreateImage =
        @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?

    /// `CGWindowListCreateImage`, obsoleted in the macOS 15 SDK but still exported. Used only to snapshot
    /// InstantTab's own windows, which needs no Screen Recording permission.
    private static let windowListCreateImage = symbol("CGWindowListCreateImage", as: WindowListCreateImage.self)

    public static func captureOwnWindow(_ windowId: CGWindowID) -> CGImage? {
        windowListCreateImage?(.null, .optionIncludingWindow, windowId, [.boundsIgnoreFraming, .bestResolution])?
            .takeRetainedValue()
    }
}
