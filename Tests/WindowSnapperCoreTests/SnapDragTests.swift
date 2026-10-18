import CoreGraphics
import Testing
@testable import WindowSnapperCore

struct SnapDragTests {
    private let start = CGRect(x: 960, y: 25, width: 960, height: 1055)

    @Test func aMoveKeepsTheSize() {
        #expect(SnapDrag.classify(start: start, now: start.offsetBy(dx: -40, dy: 12)) == .moving)
        #expect(SnapDrag.classify(start: start, now: start.offsetBy(dx: 1, dy: 0)) == .moving)
        #expect(SnapDrag.classify(start: start, now: start) == .notYet)
    }

    @Test func draggingTheLeftOrTopEdgeIsAResize() {
        for step: CGFloat in [1, 2, 30] {
            let left = CGRect(x: start.minX - step, y: start.minY, width: start.width + step, height: start.height)
            #expect(SnapDrag.classify(start: start, now: left) == .other)
            let top = CGRect(x: start.minX, y: start.minY + step, width: start.width, height: start.height - step)
            #expect(SnapDrag.classify(start: start, now: top) == .other)
        }
    }

    @Test func unsnappingKeepsTheGrabUnderThePointer() {
        // Grabbed a quarter of the way across, the pointer since moved 100 to the left.
        let grab = CGPoint(x: start.minX + 240, y: 40)
        let frame = SnapDrag.unsnapped(start.offsetBy(dx: -100, dy: 0), grabbedAt: grab, start: start, previousSize: CGSize(width: 800, height: 600), pointer: CGPoint(x: grab.x - 100, y: 40))
        #expect(frame == CGRect(x: grab.x - 100 - 200, y: 25, width: 800, height: 600))
    }
}
