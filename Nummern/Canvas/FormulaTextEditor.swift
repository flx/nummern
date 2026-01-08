import AppKit
import SwiftUI

struct FormulaTextHighlight: Hashable {
    let location: Int
    let length: Int
    let color: NSColor
}

enum EditorMoveDirection: Equatable {
    case none
    case up
    case down
    case left
    case right
}

struct FormulaTextEditor: NSViewRepresentable {
    @Binding var text: String
    let highlights: [FormulaTextHighlight]
    let font: NSFont
    let isFirstResponder: Bool
    let onSubmit: (EditorMoveDirection) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> FormulaNSTextView {
        let textView = FormulaNSTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.font = font
        textView.textContainerInset = NSSize(width: 4, height: 2)
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = true
        textView.textContainer?.lineBreakMode = .byClipping
        textView.string = text
        return textView
    }

    func updateNSView(_ nsView: FormulaNSTextView, context: Context) {
        nsView.onSubmit = onSubmit
        nsView.onCancel = onCancel
        nsView.font = font
        if nsView.string != text {
            context.coordinator.isUpdating = true
            nsView.string = text
            context.coordinator.isUpdating = false
        }
        applyHighlights(in: nsView)
        if isFirstResponder,
           nsView.window?.firstResponder != nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    private func applyHighlights(in textView: NSTextView) {
        guard let textStorage = textView.textStorage else {
            return
        }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let selectedRange = textView.selectedRange()
        textStorage.beginEditing()
        textStorage.setAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: fullRange)
        for highlight in highlights {
            guard highlight.location >= 0,
                  highlight.length > 0,
                  highlight.location + highlight.length <= textStorage.length else {
                continue
            }
            let range = NSRange(location: highlight.location, length: highlight.length)
            textStorage.addAttribute(.foregroundColor, value: highlight.color, range: range)
        }
        textStorage.endEditing()
        if selectedRange.location + selectedRange.length <= textStorage.length {
            textView.setSelectedRange(selectedRange)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var isUpdating = false

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else {
                return
            }
            text = textView.string
        }
    }
}

final class FormulaNSTextView: NSTextView {
    var onSubmit: ((EditorMoveDirection) -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return, Enter
            let move: EditorMoveDirection = event.modifierFlags.contains(.shift) ? .up : .down
            onSubmit?(move)
        case 48: // Tab
            let move: EditorMoveDirection = event.modifierFlags.contains(.shift) ? .left : .right
            onSubmit?(move)
        case 53: // Escape
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }
}
