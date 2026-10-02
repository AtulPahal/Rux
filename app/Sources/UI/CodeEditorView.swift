import AppKit

// MARK: - Line Number Gutter View
public final class LineNumberGutterView: NSView {
    public weak var textView: NSTextView?
    
    public override var isFlipped: Bool { true }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard let textView = textView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return
        }
        
        // Background
        IDETheme.sidebarBg.setFill()
        dirtyRect.fill()
        
        // Right border
        IDETheme.border.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.maxX - 0.5, y: dirtyRect.minY))
        path.line(to: NSPoint(x: bounds.maxX - 0.5, y: dirtyRect.maxY))
        path.lineWidth = 1
        path.stroke()
        
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let string = textView.string as NSString
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        
        // Count line index
        var lineNumber = 1
        var idx = 0
        while idx < charRange.location && idx < string.length {
            let lineRange = string.lineRange(for: NSRange(location: idx, length: 0))
            lineNumber += 1
            idx = NSMaxRange(lineRange)
        }
        
        // Render visible lines
        var charIdx = charRange.location
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: IDETheme.textDim
        ]
        
        while charIdx <= NSMaxRange(charRange) && charIdx < string.length {
            let lineRange = string.lineRange(for: NSRange(location: charIdx, length: 0))
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lineGlyphRange.location, effectiveRange: nil)
            
            let y = lineRect.minY - visibleRect.minY + 4
            let numStr = "\(lineNumber)" as NSString
            let strSize = numStr.size(withAttributes: attrs)
            let drawPoint = NSPoint(x: bounds.width - strSize.width - 8, y: y)
            
            numStr.draw(at: drawPoint, withAttributes: attrs)
            
            lineNumber += 1
            charIdx = NSMaxRange(lineRange)
        }
    }
}

// MARK: - Modern Lua Code Editor View
public final class CodeEditorView: FlippedView, NSTextViewDelegate {
    public var onTextChange: ((String) -> Void)?
    public var onCursorChange: ((Int, Int) -> Void)?
    
    private let scrollView = NSScrollView()
    public let textView = NSTextView()
    private let gutterView = LineNumberGutterView()
    private let gutterWidth: CGFloat = 42
    
    public var isWordWrapEnabled: Bool = true {
        didSet {
            applyWordWrap()
        }
    }
    
    private var isHighlighting = false
    public var text: String {
        get { textView.string }
        set {
            guard textView.string != newValue else { return }
            textView.string = newValue
            highlightSyntax()
            gutterView.needsDisplay = true
        }
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }
    
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = IDETheme.editorBg.cgColor
        
        // 1. Line Gutter
        gutterView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gutterView)
        
        // 2. Scroll View
        scrollView.drawsBackground = true
        scrollView.backgroundColor = IDETheme.editorBg
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        
        // 3. Text View
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = IDETheme.monoFont
        textView.textColor = IDETheme.text
        textView.backgroundColor = IDETheme.editorBg
        textView.insertionPointColor = .white
        textView.delegate = self
        textView.textContainerInset = NSSize(width: 10, height: 6)
        
        scrollView.documentView = textView
        gutterView.textView = textView
        
        // Sync gutter redraw on scroll
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        
        NSLayoutConstraint.activate([
            gutterView.topAnchor.constraint(equalTo: topAnchor),
            gutterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutterView.bottomAnchor.constraint(equalTo: bottomAnchor),
            gutterView.widthAnchor.constraint(equalToConstant: gutterWidth),
            
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyWordWrap()
    }
    
    public func applyWordWrap() {
        if isWordWrapEnabled {
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            if let container = textView.textContainer {
                container.widthTracksTextView = true
                container.containerSize = NSSize(width: max(scrollView.contentSize.width, 200), height: CGFloat.greatestFiniteMagnitude)
            }
        } else {
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            if let container = textView.textContainer {
                container.widthTracksTextView = false
                container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            }
        }
        textView.sizeToFit()
        textView.needsLayout = true
        textView.needsDisplay = true
        gutterView.needsDisplay = true
    }
    
    public func toggleWordWrap() -> Bool {
        isWordWrapEnabled.toggle()
        return isWordWrapEnabled
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleScroll() {
        gutterView.needsDisplay = true
    }
    
    public func focus() {
        window?.makeFirstResponder(textView)
    }
    
    // MARK: - NSTextViewDelegate
    
    public func textDidChange(_ notification: Notification) {
        gutterView.needsDisplay = true
        highlightSyntax()
        onTextChange?(textView.string)
        updateCursorPosition()
    }
    
    public func textViewDidChangeSelection(_ notification: Notification) {
        updateCursorPosition()
    }
    
    private func updateCursorPosition() {
        let selectedRange = textView.selectedRange()
        let string = textView.string as NSString
        let loc = min(selectedRange.location, string.length)
        
        var lineNumber = 1
        var colNumber = 1
        var lineStart = 0
        
        for i in 0..<loc {
            if string.character(at: i) == 10 { // \n
                lineNumber += 1
                lineStart = i + 1
            }
        }
        colNumber = loc - lineStart + 1
        onCursorChange?(lineNumber, colNumber)
    }
    
    // MARK: - Lua / Luau Syntax Highlighter
    
    private func highlightSyntax() {
        guard !isHighlighting else { return }
        isHighlighting = true
        defer { isHighlighting = false }
        
        guard let textStorage = textView.textStorage else { return }
        let rawString = textStorage.string
        let fullRange = NSRange(location: 0, length: (rawString as NSString).length)
        
        textStorage.beginEditing()
        
        // Base Attributes
        textStorage.addAttributes([
            .font: IDETheme.monoFont,
            .foregroundColor: IDETheme.text
        ], range: fullRange)
        
        // 1. Strings: "..." and '...'
        applyRegex(pattern: "\"[^\"\\\\]*(?:\\\\.[^\"\\\\]*)*\"|'[^'\\\\]*(?:\\\\.[^'\\\\]*)*'", color: IDETheme.string, in: textStorage)
        
        // 2. Multiline Strings: [[...]]
        applyRegex(pattern: "\\[\\[[\\s\\S]*?\\]\\]", color: IDETheme.string, in: textStorage)
        
        // 3. Numbers: 0x[0-9a-fA-F]+ or digits
        applyRegex(pattern: "\\b(?:0x[0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b", color: IDETheme.number, in: textStorage)
        
        // 4. Built-in Globals & Functions: game, loadstring, HttpGet, print, etc.
        let builtins = "\\b(?:game|workspace|Instance|loadstring|HttpGet|HttpPost|print|warn|error|assert|tostring|tonumber|type|typeof|pcall|xpcall|select|pairs|ipairs|next|table|string|math|task|wait|spawn|delay|tick|time|getgenv|getfenv|setfenv|newcclosure|hookfunction|hookmetamethod|Drawing|Vector2|Color3)\\b"
        applyRegex(pattern: builtins, color: IDETheme.builtinFunc, in: textStorage)
        
        // 5. Keywords: local, function, end, if, then, else, etc.
        let keywords = "\\b(?:local|function|end|if|then|else|elseif|return|for|while|do|repeat|until|in|not|and|or|true|false|nil|break)\\b"
        applyRegex(pattern: keywords, color: IDETheme.keyword, in: textStorage)
        
        // 6. Comments: --... and --[[...]]
        applyRegex(pattern: "--\\[\\[[\\s\\S]*?\\]\\]|--.*$", color: IDETheme.comment, in: textStorage)
        
        textStorage.endEditing()
    }
    
    private func applyRegex(pattern: String, color: NSColor, in textStorage: NSTextStorage) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
        let str = textStorage.string
        let matches = regex.matches(in: str, options: [], range: NSRange(location: 0, length: (str as NSString).length))
        for match in matches {
            textStorage.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
