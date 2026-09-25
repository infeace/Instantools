import CoreGraphics
import Testing
@testable import AppSwitcherCore

struct NameLabelTests {
    // Four 100pt tiles after 14pt of padding: tile centers at 64, 164, 264 and 364.
    private let row: ClosedRange<CGFloat> = 14...414

    private func span(_ textWidth: CGFloat, under midX: CGFloat, maxWidth: CGFloat = 250, row: ClosedRange<CGFloat>? = nil) -> (x: CGFloat, width: CGFloat) {
        NameLabel.span(textWidth: textWidth, maxWidth: maxWidth, centeredOn: midX, within: row ?? self.row)
    }

    @Test func shortNamesAreCenteredUnderEveryTile() {
        for midX: CGFloat in [64, 164, 264, 364] {
            let label = span(40, under: midX)
            #expect(label.width == 40)
            #expect(label.x + label.width / 2 == midX)
        }
    }

    @Test func longNamesMoveOnlyAsFarAsTheEdge() {
        #expect(span(180, under: 64) == (x: 14, width: 180))
        #expect(span(180, under: 364) == (x: 234, width: 180))
        #expect(span(180, under: 164) == (x: 74, width: 180))
    }

    @Test func widthIsCappedByMaxWidthAndRow() {
        #expect(span(400, under: 164).width == 250)
        #expect(span(300, under: 64, row: 14...214) == (x: 14, width: 200))
    }

    @Test func oddWidthsLandOnWholePoints() {
        let label = span(39, under: 64)
        #expect(label.x == label.x.rounded())
        #expect(abs(label.x + label.width / 2 - 64) <= 0.5)
    }
}
