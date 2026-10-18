import CoreGraphics
import Testing
@testable import WindowSnapperCore

struct SnapZonesTests {
    private let main = SnapScreen(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), visible: CGRect(x: 0, y: 25, width: 1920, height: 1055))
    private let side = SnapScreen(frame: CGRect(x: 1920, y: -400, width: 1080, height: 1920), visible: CGRect(x: 1920, y: -400, width: 1080, height: 1920))

    private func zone(_ x: CGFloat, _ y: CGFloat) -> SnapAction? {
        SnapZones.action(at: CGPoint(x: x, y: y), screens: [main, side])?.action
    }

    @Test func landscapeEdges() {
        #expect(zone(0, 500) == .leftHalf)
        #expect(zone(1919, 500) == .rightHalf)
        #expect(zone(900, 0) == .maximize)
        #expect(zone(100, 1079) == .firstThird)
        #expect(zone(960, 1079) == .centerThird)
        #expect(zone(1800, 1079) == .lastThird)
    }

    @Test func corners() {
        #expect(zone(0, 10) == .topLeft)
        #expect(zone(20, 0) == .topLeft)
        #expect(zone(1919, 0) == .topRight)
        #expect(zone(0, 1079) == .bottomLeft)
        #expect(zone(1900, 1079) == .bottomRight)
    }

    @Test func portraitEdges() {
        #expect(zone(2400, -400) == .topHalf)
        #expect(zone(2400, 1519) == .bottomHalf)
        #expect(zone(2999, -100) == .firstThird)
        #expect(zone(2999, 600) == .centerThird)
        #expect(zone(2999, 1300) == .lastThird)
    }

    @Test func awayFromTheEdgesNothingSnaps() {
        #expect(zone(900, 500) == nil)
        #expect(zone(8, 500) == nil)
        #expect(zone(5000, 500) == nil)
    }

    @Test func aSharedEdgeBelongsToTheMonitorThePointerIsOn() {
        #expect(zone(1919, 500) == .rightHalf)
        #expect(zone(1920, 600) == .centerThird)
        #expect(SnapZones.action(at: CGPoint(x: 1920, y: 600), screens: [main, side])?.screen == 1)
    }

    @Test func portraitCorners() {
        #expect(zone(1920, -400) == .topLeft)
        #expect(zone(2999, 1519) == .bottomRight)
    }

    @Test func reportsTheScreen() {
        #expect(SnapZones.action(at: CGPoint(x: 2400, y: -400), screens: [main, side])?.screen == 1)
    }
}
