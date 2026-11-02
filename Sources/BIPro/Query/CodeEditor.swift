import AppKit
import PBIXKit
import SwiftUI

enum CodeLanguage {
    case dax, tmdl
}

/// NSTextView-based editor with a line-number gutter and regex syntax highlighting.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var language: CodeLanguage
    var isEditable = true
    var measures: [ModelMetadata.Measure] = []
    /// Vùng chọn hiện tại (UTF-16), cập nhật khi người dùng chọn. Nil nếu không cần theo dõi.
    var selection: Binding<NSRange>? = nil
    /// Yêu cầu đưa con trỏ tới offset UTF-16 này; editor áp rồi đặt lại về nil.
    var cursorRequest: Binding<Int?>? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = Coordinator.font
        textView.textColor = Coordinator.plain
        textView.backgroundColor = .white
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.delegate = context.coordinator
        textView.string = text
        context.coordinator.textView = textView

        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: context.coordinator,
            userInfo: nil
        )
        textView.addTrackingArea(tracking)

        let ruler = LineNumberRuler(textView: textView)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        // macOS 14+ no longer clips views by default; keep the gutter inside the editor.
        scroll.clipsToBounds = true
        ruler.clipsToBounds = true

        context.coordinator.highlight(textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        textView.isEditable = isEditable
        if textView.string != text {
            context.coordinator.hidePopover()
            textView.string = text
            context.coordinator.highlight(textView)
            scroll.verticalRulerView?.needsDisplay = true
        }
        if let request = cursorRequest, let offset = request.wrappedValue {
            let location = min(max(0, offset), (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.scrollRangeToVisible(NSRange(location: location, length: 0))
            textView.window?.makeFirstResponder(textView)
            DispatchQueue.main.async { request.wrappedValue = nil }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        weak var textView: NSTextView?
        private var currentPopover: NSPopover?
        private var currentTokenRange: NSRange?
        private var hoverTimer: Timer?

        init(_ parent: CodeEditor) { self.parent = parent }

        static let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        static let plain = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        static let keyword = NSColor(srgbRed: 0.0, green: 0.35, blue: 0.70, alpha: 1)      // #005AB3
        static let function = NSColor(srgbRed: 0.29, green: 0.28, blue: 0.82, alpha: 1)    // indigo
        static let string = NSColor(srgbRed: 0.10, green: 0.50, blue: 0.24, alpha: 1)
        static let table = NSColor(srgbRed: 0.60, green: 0.25, blue: 0.0, alpha: 1)        // tertiary
        static let comment = NSColor(srgbRed: 0.56, green: 0.56, blue: 0.58, alpha: 1)
        static let number = NSColor(srgbRed: 0.75, green: 0.33, blue: 0.0, alpha: 1)

        func textDidChange(_ notification: Notification) {
            hidePopover()
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            highlight(textView)
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let binding = parent.selection, let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            DispatchQueue.main.async { binding.wrappedValue = range }
        }

        @objc(mouseMoved:) func mouseMoved(with event: NSEvent) {
            guard let textView, !parent.measures.isEmpty else {
                hidePopover()
                return
            }
            let point = textView.convert(event.locationInWindow, from: nil)
            guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
                hidePopover()
                return
            }
            let pointInContainer = NSPoint(
                x: point.x - textView.textContainerInset.width,
                y: point.y - textView.textContainerInset.height
            )
            let glyphIndex = layoutManager.glyphIndex(for: pointInContainer, in: textContainer)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            guard lineRect.contains(pointInContainer) else {
                hidePopover()
                return
            }
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            guard let result = MeasureHover.lookupToken(text: textView.string, utf16Offset: charIndex, measures: parent.measures) else {
                hidePopover()
                return
            }

            if let currentRange = currentTokenRange, currentRange == result.range {
                return
            }

            hoverTimer?.invalidate()
            if currentPopover != nil {
                currentPopover?.close()
                currentPopover = nil
                currentTokenRange = nil
            }

            let measure = result.measure
            let tokenRange = result.range
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.showPopover(for: measure, range: tokenRange, in: textView)
            }
        }

        @objc(mouseExited:) func mouseExited(with event: NSEvent) {
            hidePopover()
        }

        func hidePopover() {
            hoverTimer?.invalidate()
            hoverTimer = nil
            if let popover = currentPopover {
                popover.close()
                currentPopover = nil
                currentTokenRange = nil
            }
        }

        private func showPopover(for measure: ModelMetadata.Measure, range: NSRange, in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerInset.width
            rect.origin.y += textView.textContainerInset.height

            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            // Luôn sáng như Power BI (O14); mặc định NSPopover có nền mờ tối theo vibrancy, khó đọc.
            popover.appearance = NSAppearance(named: .aqua)
            let hosting = NSHostingController(rootView: MeasureTooltipView(measure: measure))
            popover.contentViewController = hosting
            popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)

            self.currentPopover = popover
            self.currentTokenRange = range
        }

        func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let text = storage.string as NSString
            let full = NSRange(location: 0, length: text.length)
            storage.beginEditing()
            storage.setAttributes([.font: Self.font, .foregroundColor: Self.plain], range: full)
            for (pattern, color) in rules {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                regex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
                    if let range = match?.range { storage.addAttribute(.foregroundColor, value: color, range: range) }
                }
            }
            storage.endEditing()
        }

        private var rules: [(String, NSColor)] {
            switch parent.language {
            case .dax:
                return [
                    (#"\b\d+(\.\d+)?\b"#, Self.number),
                    (#"\b[A-Z][A-Z0-9\.]*(?=\s*\()"#, Self.function),
                    (#"(?i)\b(EVALUATE|DEFINE|MEASURE|VAR|RETURN|ORDER BY|ASC|DESC|START AT|TABLE|COLUMN|IN|NOT|AND|OR|TRUE|FALSE)\b"#, Self.keyword),
                    (#"'[^'\n]*'"#, Self.table),
                    (#"\[[^\]\n]*\]"#, Self.keyword),
                    (#""[^"\n]*""#, Self.string),
                    (#"(//|--).*$"#, Self.comment),
                ]
            case .tmdl:
                return [
                    (#"^\s*(model|table|column|measure|hierarchy|level|partition|relationship|ref|role|cultureInfo|annotation|expression)\b"#, Self.keyword),
                    (#"^\s*[a-zA-Z]+(?=:)"#, Self.function),
                    (#"'[^'\n]*'"#, Self.table),
                    (#""[^"\n]*""#, Self.string),
                    (#"(//).*$"#, Self.comment),
                ]
            }
        }
    }
}

/// Line numbers drawn in the scroll view's vertical ruler.
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        ruleThickness = 40
        clientView = textView
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification,
                                               object: textView.enclosingScrollView?.contentView)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func refresh() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        NSColor(srgbRed: 0.965, green: 0.965, blue: 0.97, alpha: 1).setFill()
        bounds.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(srgbRed: 0.56, green: 0.56, blue: 0.58, alpha: 1),
        ]
        let text = textView.string as NSString
        let visible = textView.visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = text.substring(to: chars.location).components(separatedBy: "\n").count
        var index = chars.location
        let offset = convert(NSPoint.zero, from: textView).y + textView.textContainerInset.height
        while index <= NSMaxRange(chars) {
            let lineRange = text.lineRange(for: NSRange(location: min(index, max(0, text.length - 1)), length: 0))
            let glyph = layout.glyphRange(forCharacterRange: NSRange(location: lineRange.location, length: 0), actualCharacterRange: nil)
            let frame = layout.lineFragmentRect(forGlyphAt: min(glyph.location, max(0, layout.numberOfGlyphs - 1)), effectiveRange: nil)
            let label = "\(line)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: frame.minY + offset), withAttributes: attributes)
            line += 1
            if NSMaxRange(lineRange) <= index || NSMaxRange(lineRange) >= text.length { break }
            index = NSMaxRange(lineRange)
        }
    }
}

/// Tooltip khi rê chuột lên measure, theo Power BI (O14): dải tiêu đề xám nhạt "Measure <tên>",
/// bên dưới là biểu thức DAX trên nền trắng, chữ đậm màu.
struct MeasureTooltipView: View {
    let measure: ModelMetadata.Measure

    private static let headerFill = Color(red: 0.95, green: 0.95, blue: 0.95)
    private static let kindText = Color(red: 0.38, green: 0.37, blue: 0.36)
    private static let ink = Color(red: 0.14, green: 0.14, blue: 0.14)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Measure").font(.system(size: 12, weight: .semibold)).foregroundStyle(Self.kindText)
                Text(measure.name).font(.system(size: 12)).foregroundStyle(Self.ink)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Self.headerFill)
            let expression = measure.expression.trimmingCharacters(in: .whitespacesAndNewlines)
            if !expression.isEmpty {
                Text(expression)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Self.ink)
                    .lineLimit(12)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
            }
        }
        .frame(minWidth: 180, maxWidth: 480, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
