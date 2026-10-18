import CoreGraphics
import Foundation
import Testing
@testable import SpruceKit

private let ctrlOptCmd: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

@Test func standardComboMatches() {
    #expect(KeyCombo.standard.matches(keyCode: 32, flags: ctrlOptCmd))
    #expect(!KeyCombo.standard.matches(keyCode: 31, flags: ctrlOptCmd))
}

@Test func exactModifiersOnly() {
    #expect(!KeyCombo.standard.matches(keyCode: 32, flags: ctrlOptCmd.union(.maskShift)))
    #expect(!KeyCombo.standard.matches(keyCode: 32, flags: [.maskControl, .maskCommand]))
    #expect(!KeyCombo.standard.matches(keyCode: 32, flags: []))
}

@Test func ignoresLockAndDeviceFlags() {
    // Caps Lock, Fn, the numeric-pad flag and device-specific bits (0x8 is the left ⌘ bit) must not stop the combo.
    let noisy = ctrlOptCmd.union([.maskAlphaShift, .maskSecondaryFn, .maskNumericPad, CGEventFlags(rawValue: 0x8)])
    #expect(KeyCombo.standard.matches(keyCode: 32, flags: noisy))
}

@Test func needsTwoModifiers() {
    #expect(KeyCombo.standard.isValid)
    #expect(KeyCombo(keyCode: 32, modifiers: [.maskControl, .maskShift], key: "U").isValid)
    #expect(!KeyCombo(keyCode: 32, modifiers: [.maskCommand], key: "U").isValid)
    #expect(!KeyCombo(keyCode: 32, modifiers: [], key: "U").isValid)
}

@Test func keepsOnlyTheFourModifiers() {
    let combo = KeyCombo(keyCode: 32, modifiers: ctrlOptCmd.union(.maskAlphaShift), key: "U")
    #expect(combo == .standard)
}

@Test func displayUsesAppleOrder() {
    #expect(KeyCombo.standard.display == "⌃⌥⌘U")
    #expect(KeyCombo(keyCode: 2, modifiers: [.maskCommand, .maskShift, .maskControl, .maskAlternate], key: "D").display == "⌃⌥⇧⌘D")
}

@Test func rawValueRoundTrip() {
    let combo = KeyCombo(keyCode: 2, modifiers: [.maskShift, .maskCommand], key: "D")
    #expect(KeyCombo(rawValue: combo.rawValue) == combo)
    #expect(KeyCombo(rawValue: "") == nil)
    #expect(KeyCombo(rawValue: "x:y:z") == nil)
    #expect(KeyCombo(rawValue: "32:\(CGEventFlags.maskCommand.rawValue):U") == nil) // only one modifier
}

@Test func expiresAtDuration() {
    let start = Date(timeIntervalSince1970: 1_000)
    let lock = ScreenLock(combo: .standard, duration: 120, start: start)
    #expect(lock.remaining(at: start) == 120)
    #expect(!lock.isExpired(at: start.addingTimeInterval(119.9)))
    #expect(lock.isExpired(at: start.addingTimeInterval(120)))
    #expect(lock.remaining(at: start.addingTimeInterval(500)) == 0)
}

@Test func countdownRoundsUp() {
    let start = Date(timeIntervalSince1970: 1_000)
    let lock = ScreenLock(combo: .standard, duration: 120, start: start)
    #expect(lock.countdown(at: start) == "2:00")
    #expect(lock.countdown(at: start.addingTimeInterval(54.5)) == "1:06")
    #expect(lock.countdown(at: start.addingTimeInterval(119.5)) == "0:01")
    #expect(lock.countdown(at: start.addingTimeInterval(130)) == "0:00")
}

@Test func durationIsClamped() {
    let start = Date(timeIntervalSince1970: 1_000)
    #expect(ScreenLock(combo: .standard, duration: 0, start: start).remaining(at: start) == ScreenLock.durations.lowerBound)
    #expect(ScreenLock(combo: .standard, duration: 99_999, start: start).remaining(at: start) == ScreenLock.durations.upperBound)
    #expect(ScreenLock.defaultDuration == 120)
}
