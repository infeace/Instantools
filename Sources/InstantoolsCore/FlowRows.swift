/// Breaks items into rows the way text wraps into lines, for chips that wrap in Settings.
public enum FlowRows {
    /// The items of each row, in order. An item wider than `maxWidth` gets a row of its own.
    public static func rows(widths: [Double], maxWidth: Double, spacing: Double) -> [Range<Int>] {
        var rows: [Range<Int>] = []
        var start = 0
        var width = 0.0
        for (index, itemWidth) in widths.enumerated() {
            if index > start, width + spacing + itemWidth > maxWidth {
                rows.append(start..<index)
                start = index
                width = itemWidth
            } else {
                width += (index > start ? spacing : 0) + itemWidth
            }
        }
        if start < widths.count { rows.append(start..<widths.count) }
        return rows
    }
}
