import AppKit

public struct EditorTabItem: Identifiable, Equatable {
    public let id: String
    public var title: String
    public var content: String
    public var isModified: Bool
    
    public init(id: String = UUID().uuidString, title: String, content: String, isModified: Bool = false) {
        self.id = id
        self.title = title
        self.content = content
        self.isModified = isModified
    }
}

public final class EditorTabBarView: FlippedView {
    // Callbacks
    public var onSelectTab: ((Int) -> Void)?
    public var onCloseTab: ((Int) -> Void)?
    public var onNewTab: (() -> Void)?
    public var onExecute: (() -> Void)?
    public var onToggleWordWrap: (() -> Void)?
    
    // Model
    public private(set) var tabs: [EditorTabItem] = []
    public private(set) var activeIndex: Int = 0
    public var isWordWrapActive: Bool = true {
        didSet {
            updateWrapButtonState()
        }
    }
    
    // UI Stacks
    private let leftStack = NSStackView()
    private let rightStack = NSStackView()
    private let addTabButton = NSButton()
    
    // Right Action Buttons
    public let executeButton = NSButton()
    public let wrapButton = NSButton()
    
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
        layer?.backgroundColor = IDETheme.tabBarBg.cgColor
        
        // Bottom border
        let bottomBorder = NSBox()
        bottomBorder.boxType = .custom
        bottomBorder.borderWidth = 0
        bottomBorder.fillColor = IDETheme.border
        bottomBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBorder)
        
        // 1. Left Stack for Tabs
        leftStack.orientation = .horizontal
        leftStack.spacing = 6
        leftStack.alignment = .centerY
        leftStack.wantsLayer = true
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftStack)
        
        // 2. Right Stack for Actions
        rightStack.orientation = .horizontal
        rightStack.spacing = 8
        rightStack.alignment = .centerY
        rightStack.wantsLayer = true
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rightStack)
        // Word Wrap Toggle Button (↩ Wrap)
        wrapButton.title = "↩ Wrap"
        wrapButton.isBordered = false
        wrapButton.font = .systemFont(ofSize: 11, weight: .bold)
        wrapButton.contentTintColor = IDETheme.accent
        wrapButton.target = self
        wrapButton.action = #selector(handleToggleWrap)
        wrapButton.toolTip = "Toggle Word Wrap (ON/OFF)"
        rightStack.addArrangedSubview(wrapButton)
        
        // Execute / Run Button (▶ Run)
        executeButton.title = "▶  Run"
        executeButton.isBordered = false
        executeButton.font = .systemFont(ofSize: 11, weight: .bold)
        executeButton.contentTintColor = IDETheme.green
        executeButton.target = self
        executeButton.action = #selector(handleExecute)
        executeButton.toolTip = "Execute Lua Script in Target Process (⌘R)"
        rightStack.addArrangedSubview(executeButton)
        
        // '+' button for adding tabs
        addTabButton.title = "+"
        addTabButton.font = .systemFont(ofSize: 13, weight: .bold)
        addTabButton.isBordered = false
        addTabButton.contentTintColor = IDETheme.textDim
        addTabButton.target = self
        addTabButton.action = #selector(handleAddTab)
        addTabButton.toolTip = "Create New Script Tab"
        
        NSLayoutConstraint.activate([
            bottomBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBorder.heightAnchor.constraint(equalToConstant: 1),
            
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            leftStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            leftStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -12),
            
            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rightStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            rightStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
        
        updateWrapButtonState()
    }
    
    private func updateWrapButtonState() {
        wrapButton.contentTintColor = isWordWrapActive ? IDETheme.accent : IDETheme.textDim
    }
    
    public func setTabs(_ newTabs: [EditorTabItem], active: Int) {
        self.tabs = newTabs
        self.activeIndex = min(max(0, active), max(0, newTabs.count - 1))
        renderTabs()
    }
    
    public func updateActiveTabContent(_ content: String, isModified: Bool) {
        guard activeIndex >= 0 && activeIndex < tabs.count else { return }
        tabs[activeIndex].content = content
        tabs[activeIndex].isModified = isModified
        renderTabs()
    }
    
    public func addTab(title: String, content: String) {
        let item = EditorTabItem(title: title, content: content, isModified: false)
        tabs.append(item)
        activeIndex = tabs.count - 1
        renderTabs()
        onSelectTab?(activeIndex)
    }
    
    private func renderTabs() {
        leftStack.arrangedSubviews.forEach {
            leftStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        
        for (i, tab) in tabs.enumerated() {
            let isActive = (i == activeIndex)
            let modStr = tab.isModified ? " •" : ""
            let btnTitle = " \(tab.title)\(modStr)"
            
            let btn = NSButton(title: btnTitle, target: self, action: #selector(handleTabButtonClicked(_:)))
            btn.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            btn.imagePosition = .imageLeading
            btn.isBordered = false
            btn.font = .systemFont(ofSize: 11, weight: isActive ? .bold : .medium)
            btn.contentTintColor = isActive ? IDETheme.text : IDETheme.textDim
            btn.tag = i
            
            leftStack.addArrangedSubview(btn)
        }
        
        leftStack.addArrangedSubview(addTabButton)
    }
    
    @objc private func handleTabButtonClicked(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0 && idx < tabs.count else { return }
        activeIndex = idx
        renderTabs()
        onSelectTab?(activeIndex)
    }
    
    @objc private func handleAddTab() {
        onNewTab?()
    }
    
    @objc private func handleExecute() {
        onExecute?()
    }
    
    @objc private func handleToggleWrap() {
        onToggleWordWrap?()
    }
}
