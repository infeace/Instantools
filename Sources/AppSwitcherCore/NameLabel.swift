import CoreGraphics

/// The selected app's name sits centered under its tile. Only a name that would leave the row moves,
/// and only as far as it must.
public enum NameLabel {
    public static func span(
        textWidth: CGFloat, maxWidth: CGFloat, centeredOn midX: CGFloat, within row: ClosedRange<CGFloat>
    ) -> (x: CGFloat, width: CGFloat) {
        // Whole points, so a label clamped to the right edge does not land between pixels.
        let width = min(textWidth, maxWidth, row.upperBound - row.lowerBound).rounded(.down)
        let x = min(max((midX - width / 2).rounded(), row.lowerBound), row.upperBound - width)
        return (x, width)
    }
}
