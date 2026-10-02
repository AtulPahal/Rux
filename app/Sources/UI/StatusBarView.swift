import AppKit

public final class StatusBarView: FlippedView {
    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "Ready")
    
    private let cursorLabel = NSTextField(labelWithString: "Ln 1, Col 1")
    private let spacesLabel = NSTextField(labelWithString: "Spaces: 4")
    private let encodingLabel = NSTextField(labelWithString: "LF")
    private let langLabel = NSTextField(labelWithString: "Lua")
    private let wrapLabel = NSTextField(labelWithString: "Wrap: ON")
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
        layer?.backgroundColor = IDETheme.sidebarBg.cgColor
        
        let topBorder = NSBox()
        topBorder.boxType = .separator
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBorder)
        
        // Left Stack (Connection Status)
        let leftStack = NSStackView()
        leftStack.orientation = .horizontal
        leftStack.spacing = 6
        leftStack.alignment = .centerY
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftStack)
        
        statusDot.wantsLayer = true
        statusDot.layer?.backgroundColor = IDETheme.accent.cgColor
        statusDot.layer?.cornerRadius = 3.5
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 7),
            statusDot.heightAnchor.constraint(equalToConstant: 7)
        ])
        leftStack.addArrangedSubview(statusDot)
        
        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = IDETheme.textDim
        leftStack.addArrangedSubview(statusLabel)
        
        // Right Stack (Ln, Col, Spaces, LF, Lua)
        let rightStack = NSStackView()
        rightStack.orientation = .horizontal
        rightStack.spacing = 14
        rightStack.alignment = .centerY
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rightStack)
        
        for lbl in [cursorLabel, spacesLabel, encodingLabel, langLabel, wrapLabel] {
            lbl.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            lbl.textColor = IDETheme.textDim
            rightStack.addArrangedSubview(lbl)
        }
        
        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),
            
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    public func updateCursor(line: Int, column: Int) {
        cursorLabel.stringValue = "Ln \(line), Col \(column)"
    }
    
    public func updateWordWrap(enabled: Bool) {
        wrapLabel.stringValue = enabled ? "Wrap: ON" : "Wrap: OFF"
        wrapLabel.textColor = enabled ? IDETheme.accent : IDETheme.textDim
    }
    
    public func updateConnectionStatus(text: String, isConnected: Bool) {
        statusLabel.stringValue = text
        statusDot.layer?.backgroundColor = isConnected ? IDETheme.green.cgColor : IDETheme.accent.cgColor
    }
}
