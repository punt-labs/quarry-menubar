import AppKit
import SwiftUI

// MARK: - SelectAllTextField

/// A text field that selects all text when it gains focus, matching Spotlight behavior.
///
/// SwiftUI's `TextField` positions the cursor at the end on focus. This wrapper
/// calls `selectText(nil)` on `becomeFirstResponder` so a single keystroke
/// replaces the previous query. Also intercepts Escape via `cancelOperation(_:)`.
struct SelectAllTextField: NSViewRepresentable {

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextFieldDelegate {

        // MARK: Lifecycle

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onEscape: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
            self.onEscape = onEscape
        }

        // MARK: Internal

        var onSubmit: () -> Void
        var onEscape: () -> Void

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            _text.wrappedValue = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView _: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onEscape()
                return true
            }
            return false
        }

        // MARK: Private

        @Binding private var text: String
    }

    let placeholder: String
    @Binding var text: String

    var onSubmit: () -> Void = {}
    var onEscape: () -> Void = {}

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusSelectingTextField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.sendsActionOnEndEditing = false
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onEscape = onEscape
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onEscape: onEscape)
    }

}

// MARK: - FocusSelectingTextField

/// NSTextField subclass that selects all text each time its window becomes key.
///
/// Observes `didBecomeKeyNotification` rather than using `viewDidMoveToWindow`
/// because SwiftUI calls `updateNSView` after the view is added to the window,
/// which clears any selection made during setup. The window-key notification
/// fires after the panel is fully settled, and also re-selects on every panel
/// open — matching Spotlight's behavior.
private final class FocusSelectingTextField: NSTextField {

    // MARK: Lifecycle

    deinit {
        windowObserver.flatMap { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: Internal

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObserver.flatMap { NotificationCenter.default.removeObserver($0) }
        windowObserver = nil

        guard let window else { return }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.selectText(nil)
        }
    }

    // MARK: Private

    private var windowObserver: NSObjectProtocol?
}
