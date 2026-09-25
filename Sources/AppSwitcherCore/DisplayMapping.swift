import CoreGraphics

public enum DisplayMapping {
    public static func display(for frame: CGRect, in displays: [Display]) -> UInt32? {
        var best: (id: UInt32, area: CGFloat)?
        for display in displays {
            let overlap = frame.intersection(display.frame)
            guard !overlap.isNull, !overlap.isEmpty else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) {
                best = (display.id, area)
            }
        }
        return best?.id
    }
}
