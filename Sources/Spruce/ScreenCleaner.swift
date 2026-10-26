import AppKit
import ApplicationServices
import SwiftUI
import SpruceKit

/// Locks every keyboard and pointing device behind a black overlay until the combo is pressed or the countdown ends.
/// The tap is created before any window appears, and the countdown timer ends the lock whatever the tap is doing.
@MainActor @Observable
final class ScreenCleaner {
    private(set) var lock: ScreenLock?
    private(set) var now = Date.now

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var windows: [NSWindow] = []
    @ObservationIgnored private var timer: Timer?
    /// Read by the tap callback, which runs on the main run loop.
    @ObservationIgnored fileprivate var combo = KeyCombo.standard
    /// Drawn behind the countdown. Black unless a supporter picked a scene.
    @ObservationIgnored fileprivate(set) var scene = ScreenScene.black

    /// Starts the lock, or returns why it couldn't.
    func start(combo: KeyCombo, duration: TimeInterval, scene: ScreenScene = .black) -> String? {
        guard lock == nil else { return nil }
        guard AXIsProcessTrusted() else { return "Spruce needs Accessibility access first." }
        self.combo = combo
        self.scene = scene
        // Every event type, including gestures and media keys. `.cghidEventTap` sees them before any app does.
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask.max, callback: screenCleanTap,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return "macOS didn't allow Spruce to lock the keyboard. Try switching Spruce off and on again in Accessibility settings."
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.source = source

        let lock = ScreenLock(combo: combo, duration: duration)
        self.lock = lock
        now = .now
        windows = NSScreen.screens.map { overlay(on: $0) }
        NSApp.activate()
        windows.forEach { $0.orderFrontRegardless() }
        windows.first?.makeKey()
        NSCursor.hide()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        return nil
    }

    /// Safe to call more than once.
    func stop() {
        guard lock != nil else { return }
        timer?.invalidate()
        timer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
        NSCursor.unhide()
        lock = nil
    }

    private func tick() {
        now = .now
        if lock?.isExpired(at: now) ?? true { stop() }
    }

    fileprivate func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func overlay(on screen: NSScreen) -> NSWindow {
        let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: OverlayView(cleaner: self))
        window.setFrame(screen.frame, display: true)
        return window
    }
}

/// Borderless windows can't become key by default; this one must, so it sits in front.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Swallows every event. A key-down matching the combo ends the lock; nothing else gets through.
private func screenCleanTap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let cleaner = Unmanaged<ScreenCleaner>.fromOpaque(refcon).takeUnretainedValue()
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    MainActor.assumeIsolated {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            cleaner.reenableTap()
        case .keyDown where cleaner.combo.matches(keyCode: keyCode, flags: flags):
            DispatchQueue.main.async { cleaner.stop() }
        default:
            break
        }
    }
    return nil
}

/// What's on screen while locked: dark, quiet, with the countdown and the way out.
struct OverlayView: View {
    let cleaner: ScreenCleaner

    var body: some View {
        ZStack {
            ScreenSceneView(scene: cleaner.scene)
            if let lock = cleaner.lock {
                VStack(spacing: 14) {
                    Text(lock.countdown(at: cleaner.now))
                        .font(.system(size: 72, weight: .light, design: .rounded)).monospacedDigit()
                    Text("Locked for cleaning").font(.title3)
                    Text("Press \(lock.combo.display) to unlock. It unlocks by itself when the timer ends.")
                        .font(.callout)
                }
                .foregroundStyle(.white.opacity(0.35))
            }
        }
        .ignoresSafeArea()
    }
}
