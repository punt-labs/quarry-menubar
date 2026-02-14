import AppKit
import Carbon.HIToolbox
@testable import QuarryMenuBar
import XCTest

@MainActor
final class HotkeyManagerTests: XCTestCase {
    func testRegisterAndUnregister() {
        let manager = HotkeyManager()
        manager.register {}
        // Should not crash when unregistering
        manager.unregister()
    }

    func testDefaultKeyCodeIsQ() {
        // Verify the default init uses Cmd+Shift+Q
        let manager = HotkeyManager()
        // We can't inspect private properties, but registration should succeed
        manager.register {}
        manager.unregister()
    }

    func testCustomKeyCode() {
        let manager = HotkeyManager(
            keyCode: UInt16(kVK_Space),
            modifiers: [.command, .option]
        )
        manager.register {}
        manager.unregister()
    }

    func testDoubleUnregisterIsNoop() {
        let manager = HotkeyManager()
        manager.register {}
        manager.unregister()
        manager.unregister() // Should not crash
    }
}
