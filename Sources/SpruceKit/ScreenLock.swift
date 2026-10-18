import CoreGraphics
import Foundation

/// The key combo that ends Screen Clean. Only ⌃ ⌥ ⇧ ⌘ count; Caps Lock, Fn and device bits are ignored.
public struct KeyCombo: Equatable, Sendable, RawRepresentable {
    static let relevant: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    public let keyCode: Int64
    public let modifiers: CGEventFlags
    /// What to show for the key, e.g. "U".
    public let key: String

    /// ⌃⌥⌘U (kVK_ANSI_U is 32).
    public static let standard = KeyCombo(keyCode: 32, modifiers: [.maskControl, .maskAlternate, .maskCommand], key: "U")

    public init(keyCode: Int64, modifiers: CGEventFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevant)
        self.key = key
    }

    public func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == self.keyCode && flags.intersection(Self.relevant) == modifiers
    }

    /// Two modifiers at least, so wiping the keyboard can't unlock it by accident.
    public var isValid: Bool {
        [CGEventFlags.maskControl, .maskAlternate, .maskShift, .maskCommand].filter { modifiers.contains($0) }.count >= 2
    }

    public var display: String {
        let symbols: [(CGEventFlags, String)] = [(.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + key
    }

    /// "keyCode:modifiers:key", for UserDefaults.
    public var rawValue: String { "\(keyCode):\(modifiers.rawValue):\(key)" }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, let code = Int64(parts[0]), let flags = UInt64(parts[1]), !parts[2].isEmpty else { return nil }
        self.init(keyCode: code, modifiers: CGEventFlags(rawValue: flags), key: parts[2])
        guard isValid else { return nil }
    }
}

/// One Screen Clean session: when it ends by itself, and how to end it early.
public struct ScreenLock: Sendable {
    public static let defaultDuration: TimeInterval = 120
    public static let durations: ClosedRange<TimeInterval> = 30...600

    public let combo: KeyCombo
    public let ends: Date

    public init(combo: KeyCombo, duration: TimeInterval, start: Date = .now) {
        self.combo = combo
        ends = start.addingTimeInterval(min(max(duration, Self.durations.lowerBound), Self.durations.upperBound))
    }

    public func remaining(at now: Date) -> TimeInterval { max(0, ends.timeIntervalSince(now)) }
    public func isExpired(at now: Date) -> Bool { remaining(at: now) == 0 }

    /// "m:ss", rounded up so it never shows 0:00 while still locked.
    public func countdown(at now: Date) -> String {
        let seconds = Int(remaining(at: now).rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
