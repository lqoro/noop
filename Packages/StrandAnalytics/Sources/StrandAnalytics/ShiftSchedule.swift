import Foundation

/// Night-shift mode: the user's usual MAIN-sleep window, in local hours.
///
/// The detector and selector hardcode "night" as onset in [20:00, 11:00) and hold anything centered in
/// [11:00, 20:00) to the stricter daytime-nap bar. For a night-shift worker who sleeps e.g. 06:00–14:00,
/// the tail of that sleep (and any late onset after 11:00) falls in the "daytime" band. When enabled, a
/// sleep whose onset/center sits inside `sleepStartHour..<sleepEndHour` (wrapping midnight allowed) is
/// treated exactly like an overnight sleep, and the cold-start alignment anchor moves to the window's
/// center. Disabled (the default) is byte-identical to the stock behaviour.
public struct ShiftSchedule: Equatable, Sendable {
    public var enabled: Bool
    /// Local hour [0, 24) the main-sleep window opens (inclusive).
    public var sleepStartHour: Int
    /// Local hour [0, 24) the main-sleep window closes (exclusive). May be < start (wraps midnight).
    public var sleepEndHour: Int

    public init(enabled: Bool, sleepStartHour: Int, sleepEndHour: Int) {
        self.enabled = enabled
        self.sleepStartHour = ((sleepStartHour % 24) + 24) % 24
        self.sleepEndHour = ((sleepEndHour % 24) + 24) % 24
    }

    public static let off = ShiftSchedule(enabled: false, sleepStartHour: 5, sleepEndHour: 15)

    public static let enabledKey = "noop.nightShift.enabled"
    public static let startHourKey = "noop.nightShift.sleepStartHour"
    public static let endHourKey = "noop.nightShift.sleepEndHour"

    /// Read from UserDefaults (defaults: off, 05:00–15:00).
    public static func load(from defaults: UserDefaults = .standard) -> ShiftSchedule {
        ShiftSchedule(enabled: defaults.bool(forKey: enabledKey),
                      sleepStartHour: defaults.object(forKey: startHourKey) as? Int ?? 5,
                      sleepEndHour: defaults.object(forKey: endHourKey) as? Int ?? 15)
    }

    /// True when the local hour `hour` is inside the window (wrap-aware). Always false when disabled
    /// or when start == end.
    public func containsHour(_ hour: Int) -> Bool {
        guard enabled, sleepStartHour != sleepEndHour else { return false }
        if sleepStartHour < sleepEndHour { return hour >= sleepStartHour && hour < sleepEndHour }
        return hour >= sleepStartHour || hour < sleepEndHour
    }

    /// True when the unix timestamp `ts` (shifted east by `offsetSec`) falls inside the window.
    public func contains(_ ts: Int, offsetSec: Int) -> Bool {
        let local = ts + offsetSec
        let secOfDay = ((local % 86_400) + 86_400) % 86_400
        return containsHour(secOfDay / 3_600)
    }

    /// The window's center as a local time-of-day in seconds, or nil when disabled.
    public var centerSec: Int? {
        guard enabled, sleepStartHour != sleepEndHour else { return nil }
        let span = (sleepEndHour - sleepStartHour + 24) % 24
        return ((sleepStartHour * 3_600 + span * 1_800) % 86_400)
    }

    // MARK: - Process-wide current schedule

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _current: ShiftSchedule = .off

    /// The schedule the analytics read. The app sets this from Settings; tests set and reset it.
    public static var current: ShiftSchedule {
        get { lock.lock(); defer { lock.unlock() }; return _current }
        set { lock.lock(); _current = newValue; lock.unlock() }
    }
}
