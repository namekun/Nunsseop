import Testing
@testable import Nunsseop

struct SystemStatsTests {
    @Test func rateIsBytesPerSecond() {
        #expect(SystemStats.rate(previous: 1000, current: 4000, seconds: 1.5) == 2000)
        #expect(SystemStats.rate(previous: 0, current: 0, seconds: 1.5) == 0)
    }

    @Test(arguments: [
        (UInt64(5_000_000_000), UInt64(100)),
        (UInt64.max, UInt64(0)),
        (UInt64(4_294_967_295), UInt64(10)),
    ])
    func aCounterThatWentDownShowsNoTraffic(previous: UInt64, current: UInt64) {
        let rate = SystemStats.rate(previous: previous, current: current, seconds: 0.5)
        #expect(rate == 0)
        #expect(Int64(exactly: rate) != nil)
    }

    @MainActor
    @Test func bytesKeepTheLetterBBelowOneKilobyte() {
        #expect(SystemTab.bytes(0) == "0 B")
        #expect(SystemTab.bytes(512) == "512 B")
        #expect(SystemTab.bytes(1023) == "1023 B")
        #expect(SystemTab.bytes(-5) == "0 B")
    }
}
