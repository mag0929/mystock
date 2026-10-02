import Foundation
import Testing

@Suite("Smoke")
struct SmokeTests {
    @Test("Fixtures build a stable calendar date")
    func fixtureDate() {
        let date = Fixtures.makeDate(2026, 1, 10)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        #expect(parts.year == 2026)
        #expect(parts.month == 1)
        #expect(parts.day == 10)
    }
}
