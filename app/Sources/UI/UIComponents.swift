import AppKit

open class FlippedView: NSView {
    open override var isFlipped: Bool { true }
}

open class CardView: FlippedView {
    public let titleLabel = NSTextField(labelWithString: "")
    public let iconView = NSImageView()
    public let divider = NSBox()
    
    public init(title: String, icon: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor
        
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        iconView.contentTintColor = .systemPurple
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)
        
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            
            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            
            divider.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            divider.heightAnchor.constraint(equalToConstant: 1)
        ])
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public var contentTopAnchor: NSLayoutYAxisAnchor {
        divider.bottomAnchor
    }
}
