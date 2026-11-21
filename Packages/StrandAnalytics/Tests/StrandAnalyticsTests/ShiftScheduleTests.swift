import XCTest
@testable import StrandAnalytics

/// Night-shift mode: a 21:00–05:00 worker who sleeps ~06:00–13:30. Synthetic week, UTC offset 0.
final class ShiftScheduleTests: XCTestCase {
    private let day0 = 20_833 * 86_400          // a local midnight
    private let h = 3_600
    private let nightShift = ShiftSchedule(enabled: true, sleepStartHour: 5, sleepEndHour: 15)

    override func tearDown() { ShiftSchedule.current = .off; super.tearDown() }

    func testWindowMath() {
        XCTAssertTrue(nightShift.containsHour(5))
        XCTAssertTrue(nightShift.containsHour(14))
        XCTAssertFalse(nightShift.containsHour(15))
        XCTAssertFalse(nightShift.containsHour(22))
        XCTAssertEqual(nightShift.centerSec, 10 * h)
        let wrap = ShiftSchedule(enabled: true, sleepStartHour: 22, sleepEndHour: 6)
        XCTAssertTrue(wrap.containsHour(23)); XCTAssertTrue(wrap.containsHour(2)); XCTAssertFalse(wrap.containsHour(12))
        XCTAssertEqual(wrap.centerSec, 2 * h)
        XCTAssertNil(ShiftSchedule.off.centerSec)
        XCTAssertFalse(ShiftSchedule.off.containsHour(10))
    }

    func testOffIsStockBehaviour() {
        ShiftSchedule.current = .off
        XCTAssertFalse(SleepStageTotals.isOvernightOnset(day0 + 12 * h, offsetSec: 0))
        XCTAssertTrue(SleepStageTotals.isOvernightOnset(day0 + 6 * h, offsetSec: 0))
        XCTAssertTrue(SleepStager.isDaytimeCenter(.init(stage: "sleep", start: day0 + 11 * h, end: day0 + 15 * h),
                                                  tzOffsetSeconds: 0))
    }

    func testLateOnsetCountsAsNightWhenEnabled() {
        ShiftSchedule.current = nightShift
        XCTAssertTrue(SleepStageTotals.isOvernightOnset(day0 + 12 * h, offsetSec: 0))
        XCTAssertTrue(SleepStager.isOvernightOnset(day0 + 12 * h, tzOffsetSeconds: 0))
        XCTAssertFalse(SleepStager.isDaytimeCenter(.init(stage: "sleep", start: day0 + 11 * h, end: day0 + 15 * h),
                                                   tzOffsetSeconds: 0))
        // Evening still uses the stock rules (stricter bar for a 16:00–19:00 nap).
        XCTAssertTrue(SleepStager.isDaytimeCenter(.init(stage: "sleep", start: day0 + 16 * h, end: day0 + 19 * h),
                                                  tzOffsetSeconds: 0))
    }

    /// A week of shifts. Each cycle has one main day sleep plus a pre-shift evening nap. Two days have a
    /// late (after 11:00) onset that stock rules would demote to a nap. Exactly one main sleep per cycle.
    func testShiftWeekOneMainSleepPerCycle() {
        ShiftSchedule.current = nightShift
        let onsets = [6, 6, 7, 12, 6, 11, 7]     // hour of main-sleep onset, days 0–6
        for (d, onsetHour) in onsets.enumerated() {
            let base = day0 + d * 86_400
            let main = PhysiologicalSteps.SleepBlock(onset: base + onsetHour * h, end: base + (onsetHour + 6) * h,
                                                     id: "main\(d)")
            let nap = PhysiologicalSteps.SleepBlock(onset: base + 19 * h + 30 * 60, end: base + 20 * h + 15 * 60,
                                                    id: "nap\(d)")
            let out = PhysiologicalSteps.classifyForCycle([main, nap], offsetSec: 0, habitualMidsleepSec: nil)
            XCTAssertEqual(out.filter { $0.kind == .mainSleep }.map(\.id), ["main\(d)"], "day \(d)")
        }
    }

    func testStockRulesDemoteLateOnset() {
        ShiftSchedule.current = .off
        let block = PhysiologicalSteps.SleepBlock(onset: day0 + 12 * h, end: day0 + 19 * h, id: "late")
        let out = PhysiologicalSteps.classifyForCycle([block], offsetSec: 0, habitualMidsleepSec: nil)
        XCTAssertEqual(out.first?.kind, .nap)
    }

    func testColdStartAnchorMovesToWindowCenter() {
        ShiftSchedule.current = nightShift
        XCTAssertEqual(SleepStageTotals.targetMidsleepSec(nil), 10 * h)
        XCTAssertEqual(SleepStageTotals.targetMidsleepSec(3 * h), 3 * h)   // learned timing still wins
    }
}
