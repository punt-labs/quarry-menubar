import AppKit
import Carbon.HIToolbox
import os

/// Manages a global keyboard shortcut to toggle the menu bar panel.
///
/// Uses `NSEvent` global and local monitors for key events.
/// Default shortcut: Cmd+Shift+Q.
@MainActor
final class HotkeyManager {

    // MARK: Lifecycle

    init(
        keyCode: UInt16 = UInt16(kVK_ANSI_Q),
        modifiers: NSEvent.ModifierFlags = [.command, .shift]
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    deinit {
        // Monitors must be removed on the same thread they were added
        // (main thread). Since this class is @MainActor, deinit runs
        // on main. removeMonitor is safe to call with nil.
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    // MARK: Internal

    /// Start listening for the global shortcut.
    /// - Parameter handler: Called on the main actor when the shortcut is pressed.
    func register(handler: @escaping @MainActor () -> Void) {
        self.handler = handler

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleEvent(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleEvent(event)
            }
            return event
        }

        let kc = keyCode
        let mod = modifiers.rawValue
        logger.info("Registered global hotkey (keyCode=\(kc), modifiers=\(mod))")
    }

    /// Stop listening for the global shortcut.
    func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        handler = nil
        logger.info("Unregistered global hotkey")
    }

    // MARK: Private

    private let keyCode: UInt16
    private let modifiers: NSEvent.ModifierFlags
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var handler: (@MainActor () -> Void)?
    private let logger = Logger(subsystem: "com.puntlabs.quarry-menubar", category: "HotkeyManager")

    private func handleEvent(_ event: NSEvent) {
        let targetModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        guard event.keyCode == keyCode,
              event.modifierFlags.intersection(targetModifiers) == modifiers
        else {
            return
        }
        handler?()
    }
}
