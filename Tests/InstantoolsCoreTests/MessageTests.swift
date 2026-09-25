import Foundation
import Testing
@testable import InstantoolsCore

struct MessageTests {
    private func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> Value {
        let line = try #require(MessageCoding.line(value))
        #expect(line.last == 0x0A)
        #expect(line.dropLast().contains(0x0A) == false)
        return try #require(MessageCoding.decode(Value.self, from: Array(line.dropLast())))
    }

    @Test func requestIsOneSmallObject() throws {
        let line = try #require(MessageCoding.line(HostRequest(request: .status)))
        #expect(String(decoding: line, as: UTF8.self) == "{\"request\":\"status\"}\n")
        #expect(try roundTrip(HostRequest(request: .status)) == HostRequest(request: .status))
    }

    @Test func readyEventIsOnlyTheEvent() throws {
        let line = try #require(MessageCoding.line(ToolMessage(event: .ready)))
        #expect(String(decoding: line, as: UTF8.self) == "{\"event\":\"ready\"}\n")
        #expect(try roundTrip(ToolMessage(event: .ready)) == ToolMessage(event: .ready))
    }

    @Test func appSwitcherStatusRoundTrips() throws {
        let status = AppSwitcherStatus(
            latencySamples: [6_100_000, 7_400_000, UInt64.max],
            focusedDisplay: 3,
            recentApps: [
                .init(pid: 501, name: "Finder"),
                .init(pid: 502, name: "Notes \"draft\"\nline"),
            ],
            handlesCmdTab: false
        )
        let message = ToolMessage(appSwitcher: status)
        #expect(try roundTrip(message) == message)
    }

    @Test func layoutSwitcherStatusRoundTrips() throws {
        let message = ToolMessage(layoutSwitcher: LayoutSwitcherStatus(tapRunning: true))
        #expect(try roundTrip(message) == message)
    }

    @Test func layoutsFromAnOlderToolAreIgnored() {
        let line = Array(#"{"layoutSwitcher":{"tapRunning":true,"layouts":["ABC"]}}"#.utf8)
        #expect(MessageCoding.decode(ToolMessage.self, from: line) == ToolMessage(layoutSwitcher: LayoutSwitcherStatus(tapRunning: true)))
    }

    @Test func unknownFieldsAreIgnored() {
        let line = Array(#"{"id":3,"event":"ready","future":{"x":1}}"#.utf8)
        #expect(MessageCoding.decode(ToolMessage.self, from: line) == ToolMessage(event: .ready))
    }

    @Test func garbageDecodesToNil() {
        #expect(MessageCoding.decode(HostRequest.self, from: Array("not json".utf8)) == nil)
        #expect(MessageCoding.decode(HostRequest.self, from: Array(#"{"request":"nope"}"#.utf8)) == nil)
    }
}

struct LineBufferTests {
    @Test func splitsLinesAndKeepsTheRest() {
        var buffer = LineBuffer()
        #expect(buffer.append(Array("{\"a\":1}\n{\"b\"".utf8)) == [Array("{\"a\":1}".utf8)])
        #expect(buffer.append(Array(":2}\n\n{\"c\":3}\n".utf8)) == [Array("{\"b\":2}".utf8), Array("{\"c\":3}".utf8)])
        #expect(buffer.append([]) == [])
    }

    @Test func keepsALineOfExactlyTheMaximumLength() {
        var buffer = LineBuffer()
        let line = [UInt8](repeating: 0x61, count: LineBuffer.maxLineLength)
        #expect(buffer.append(line + [0x0A]) == [line])
        #expect(buffer.append(line + [0x61, 0x0A]) == [])
    }

    @Test func dropsALineThatIsTooLong() {
        var buffer = LineBuffer()
        let long = [UInt8](repeating: 0x61, count: LineBuffer.maxLineLength + 10)
        #expect(buffer.append(long) == [])
        #expect(buffer.append(Array("tail\nok\n".utf8)) == [Array("ok".utf8)])
    }
}
