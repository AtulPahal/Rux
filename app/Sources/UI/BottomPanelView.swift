import AppKit
import Combine

public enum BottomPanelTab: String, CaseIterable {
    case terminal = "TERMINAL"
    case console = "CONSOLE"
    case rconsole = "RCONSOLE"
    case problems = "PROBLEMS"
}

public final class BottomPanelView: FlippedView {
    public var onToggleCollapse: (() -> Void)?
    
    // Model
    public private(set) var activeTab: BottomPanelTab = .terminal
    public private(set) var isCollapsed: Bool = false
    
    // Tab Header
    private let tabHeaderView = FlippedView()
    private var tabButtons: [BottomPanelTab: NSButton] = [:]
    private let indicatorLine = NSView()
    private var indicatorLeadingConstraint: NSLayoutConstraint!
    private var indicatorWidthConstraint: NSLayoutConstraint!
    
    // Header Right Actions
    private let clearButton = NSButton()
    private let collapseButton = NSButton()
    
    // Content Views
    private let contentContainer = FlippedView()
    private let scrollView = NSScrollView()
    public let textView = NSTextView()
    
    // Tab Text Buffers
    private var buffers: [BottomPanelTab: String] = [
        .terminal: "Rux Mach-O Introspection Terminal\nMonitoring dynamic library injection and runtime telemetry...\n",
        .console: "Rux Script Execution Console (REPL)\nConnect to target payload on 127.0.0.1:5553 to view executed script outputs.\n",
        .rconsole: "Remote In-Game Luau Console (rconsole)\nHooked print(), warn(), and error() output from target process.\n",
        .problems: "Diagnostics & Security Status\nRun 'Darwin Mach-O Diagnostics' or check Process Explorer for Hardened Runtime warnings.\n"
    ]
    
    private var cancellables = Set<AnyCancellable>()
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        bindLogStore()
        selectTab(.terminal)
    }
    
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        bindLogStore()
        selectTab(.terminal)
    }
    
    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = IDETheme.panelBg.cgColor
        
        // Top border
        let topBorder = NSBox()
        topBorder.boxType = .separator
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBorder)
        
        // 1. Tab Header (28px height)
        tabHeaderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabHeaderView)
        
        let tabStack = NSStackView()
        tabStack.orientation = .horizontal
        tabStack.spacing = 18
        tabStack.alignment = .centerY
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabHeaderView.addSubview(tabStack)
        
        for tab in BottomPanelTab.allCases {
            let btn = NSButton(title: tab.rawValue, target: self, action: #selector(handleTabClick(_:)))
            btn.isBordered = false
            btn.font = .systemFont(ofSize: 11, weight: .bold)
            btn.contentTintColor = (tab == activeTab) ? IDETheme.text : IDETheme.textDim
            btn.tag = BottomPanelTab.allCases.firstIndex(of: tab) ?? 0
            tabButtons[tab] = btn
            tabStack.addArrangedSubview(btn)
        }
        
        // Active Indicator Underline (2px blue line)
        indicatorLine.wantsLayer = true
        indicatorLine.layer?.backgroundColor = IDETheme.accent.cgColor
        indicatorLine.layer?.cornerRadius = 1
        indicatorLine.translatesAutoresizingMaskIntoConstraints = false
        tabHeaderView.addSubview(indicatorLine)
        
        indicatorLeadingConstraint = indicatorLine.leadingAnchor.constraint(equalTo: tabHeaderView.leadingAnchor, constant: 14)
        indicatorWidthConstraint = indicatorLine.widthAnchor.constraint(equalToConstant: 60)
        
        // Right Controls: Clear & Collapse
        let rightStack = NSStackView()
        rightStack.orientation = .horizontal
        rightStack.spacing = 8
        rightStack.alignment = .centerY
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        tabHeaderView.addSubview(rightStack)
        
        clearButton.isBordered = false
        clearButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear")
        clearButton.contentTintColor = IDETheme.textDim
        clearButton.target = self
        clearButton.action = #selector(handleClear)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        rightStack.addArrangedSubview(clearButton)
        
        collapseButton.isBordered = false
        collapseButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Collapse")
        collapseButton.contentTintColor = IDETheme.textDim
        collapseButton.target = self
        collapseButton.action = #selector(handleCollapse)
        collapseButton.translatesAutoresizingMaskIntoConstraints = false
        rightStack.addArrangedSubview(collapseButton)
        
        // 2. Content Container (Bordered card matching screenshot)
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor(red: 0.059, green: 0.067, blue: 0.090, alpha: 1.0).cgColor
        contentContainer.layer?.cornerRadius = 6
        contentContainer.layer?.borderWidth = 1
        contentContainer.layer?.borderColor = IDETheme.border.cgColor
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)
        
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(scrollView)
        
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = IDETheme.monoFontSmall
        textView.textColor = IDETheme.text
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 12, height: 8)
        scrollView.documentView = textView
        
        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),
            
            tabHeaderView.topAnchor.constraint(equalTo: topAnchor),
            tabHeaderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabHeaderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabHeaderView.heightAnchor.constraint(equalToConstant: 32),
            
            tabStack.leadingAnchor.constraint(equalTo: tabHeaderView.leadingAnchor, constant: 14),
            tabStack.centerYAnchor.constraint(equalTo: tabHeaderView.centerYAnchor),
            
            indicatorLine.bottomAnchor.constraint(equalTo: tabHeaderView.bottomAnchor),
            indicatorLine.heightAnchor.constraint(equalToConstant: 2),
            indicatorLeadingConstraint,
            indicatorWidthConstraint,
            
            rightStack.trailingAnchor.constraint(equalTo: tabHeaderView.trailingAnchor, constant: -14),
            rightStack.centerYAnchor.constraint(equalTo: tabHeaderView.centerYAnchor),
            
            contentContainer.topAnchor.constraint(equalTo: tabHeaderView.bottomAnchor, constant: 4),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            
            scrollView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }
    
    private func bindLogStore() {
        LogStore.shared.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self = self, let last = items.last else { return }
                let line = "[\(last.level.rawValue)] \(last.message)\n"
                self.appendOutput(line, to: .terminal)
            }
            .store(in: &cancellables)
    }
    
    @objc private func handleTabClick(_ sender: NSButton) {
        guard sender.tag >= 0 && sender.tag < BottomPanelTab.allCases.count else { return }
        selectTab(BottomPanelTab.allCases[sender.tag])
    }
    
    public func selectTab(_ tab: BottomPanelTab) {
        activeTab = tab
        
        // Update tab buttons
        for (t, btn) in tabButtons {
            let isSel = (t == tab)
            btn.contentTintColor = isSel ? IDETheme.text : IDETheme.textDim
        }
        
        // Update indicator line
        if let activeBtn = tabButtons[tab] {
            let frame = activeBtn.frame
            indicatorLeadingConstraint.constant = activeBtn.superview?.convert(frame, to: tabHeaderView).minX ?? 14
            indicatorWidthConstraint.constant = max(frame.width, 40)
        }
        
        // Load buffer content
        textView.string = buffers[tab] ?? ""
        textView.scrollToEndOfDocument(nil)
    }
    
    public func appendOutput(_ text: String, to tab: BottomPanelTab) {
        var current = buffers[tab] ?? ""
        current += text
        // Keep buffer bounded
        if current.count > 50000 {
            current = String(current.suffix(35000))
        }
        buffers[tab] = current
        
        if activeTab == tab {
            textView.string = current
            textView.scrollToEndOfDocument(nil)
        }
    }
    
    @objc private func handleClear() {
        buffers[activeTab] = ""
        textView.string = ""
    }
    
    @objc private func handleCollapse() {
        onToggleCollapse?()
    }
}
