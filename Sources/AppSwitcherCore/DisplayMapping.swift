import CoreGraphics

public enum DisplayMapping {
    public static func display(for frame: CGRect, in displays: [Display]) -> UInt32? {
        var best: (id: UInt32, area: CGFloat)?
        for display in displays {
            let overlap = frame.intersection(display.frame)
            guard !overlap.isEmpty else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) {
                best = (display.id, area)
            }
        }
        return best?.id
    }

    /// The windows on a connected display, still front to back, and the display of each app's frontmost
    /// one. A window parked off every display counts as none, so exclusions, scopes and focusing all treat
    /// its app as windowless. With no display known nothing can be placed, so every window is kept.
    public static func placed(_ windows: [WindowRecord], on displays: [Display]) -> (windows: [WindowRecord], displayByPid: [Int32: UInt32]) {
        guard !displays.isEmpty else { return (windows, [:]) }
        var kept: [WindowRecord] = []
        var displayByPid: [Int32: UInt32] = [:]
        for window in windows {
            guard let display = display(for: window.frame, in: displays) else { continue }
            kept.append(window)
            if displayByPid[window.pid] == nil { displayByPid[window.pid] = display }
        }
        return (kept, displayByPid)
    }
}
