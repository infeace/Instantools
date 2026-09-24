import Testing
@testable import InstantTabCore

struct LatencyStatsTests {
    @Test func emptyHasNoPercentile() {
        #expect(LatencyStats().percentile(50) == nil)
    }

    @Test func nearestRankPercentiles() {
        var stats = LatencyStats(capacity: 10)
        for value in 1...10 { stats.record(UInt64(value)) }
        #expect(stats.percentile(0) == 1)
        #expect(stats.percentile(50) == 5)
        #expect(stats.percentile(95) == 10)
        #expect(stats.percentile(100) == 10)
    }

    @Test func ringOverwritesOldestSample() {
        var stats = LatencyStats(capacity: 3)
        for value: UInt64 in [100, 1, 2, 3] { stats.record(value) }
        #expect(stats.count == 3)
        #expect(stats.percentile(100) == 3)
        #expect(stats.chronological == [1, 2, 3])
        stats.record(4)
        #expect(stats.chronological == [2, 3, 4])
    }

    @Test func formatsMilliseconds() {
        #expect(LatencyStats.milliseconds(12_340_000) == "12.3ms")
        #expect(LatencyStats.milliseconds(20_060_000) == "20.1ms")
        #expect(LatencyStats.milliseconds(0) == "0.0ms")
    }
}
