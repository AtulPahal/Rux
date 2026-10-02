import AppKit

// MARK: - Flipped View for Natural Top-Down Layout
open class FlippedView: NSView {
    open override var isFlipped: Bool { true }
}

// MARK: - Modern HIG Section Card
open class GroupSectionView: FlippedView {
    public let headerContainer = NSView()
    public let iconImageView = NSImageView()
    public let titleLabel = NSTextField(labelWithString: "")
    public let subtitleLabel = NSTextField(labelWithString: "")
    public let headerTrailingContainer = NSView()
    public let contentView = FlippedView()
    public let divider = NSBox()
    
    public init(title: String, subtitle: String? = nil, iconName: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        
        updateColors()
        
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerContainer)
        
        if let icon = iconName {
            iconImageView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
            iconImageView.contentTintColor = .controlAccentColor
        }
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(iconImageView)
        
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(titleLabel)
        
        if let sub = subtitle {
            subtitleLabel.stringValue = sub
            subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
            subtitleLabel.textColor = .secondaryLabelColor
        }
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(subtitleLabel)
        
        headerTrailingContainer.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(headerTrailingContainer)
        
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)
        
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        
        NSLayoutConstraint.activate([
            headerContainer.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            headerContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            headerContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            headerContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            
            iconImageView.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 16),
            iconImageView.heightAnchor.constraint(equalToConstant: 16),
            
            titleLabel.topAnchor.constraint(equalTo: headerContainer.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            
            headerTrailingContainer.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            headerTrailingContainer.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            
            divider.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 10),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            divider.heightAnchor.constraint(equalToConstant: 1),
            
            contentView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 12),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func updateLayer() {
        super.updateLayer()
        updateColors()
    }
    
    private func updateColors() {
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor
    }
}

// MARK: - Modern Status Pill / Badge
public final class StatusPillView: NSView {
    private let dotView = NSView()
    private let label = NSTextField(labelWithString: "")
    
    public init(text: String, color: NSColor, dotVisible: Bool = true) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        
        applyStyle(text: text, color: color, dotVisible: dotVisible)
        
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3.5
        dotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotView)
        
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 20),
            
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 7),
            dotView.heightAnchor.constraint(equalToConstant: 7),
            
            label.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(text: String, color: NSColor, dotVisible: Bool = true) {
        applyStyle(text: text, color: color, dotVisible: dotVisible)
    }
    
    private func applyStyle(text: String, color: NSColor, dotVisible: Bool) {
        label.stringValue = text
        label.textColor = color
        dotView.isHidden = !dotVisible
        dotView.layer?.backgroundColor = color.cgColor
        layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
        layer?.borderColor = color.withAlphaComponent(0.35).cgColor
    }
}

// MARK: - Key-Value Metric Display Row
public final class KeyValueRowView: NSView {
    public let keyLabel = NSTextField(labelWithString: "")
    public let valueLabel = NSTextField(labelWithString: "")
    
    public init(key: String, value: String, isMonospaced: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        
        keyLabel.stringValue = key
        keyLabel.font = .systemFont(ofSize: 11, weight: .regular)
        keyLabel.textColor = .secondaryLabelColor
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyLabel)
        
        valueLabel.stringValue = value
        valueLabel.font = isMonospaced ? .monospacedSystemFont(ofSize: 11, weight: .medium) : .systemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .labelColor
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 18),
            keyLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            keyLabel.widthAnchor.constraint(equalToConstant: 110),
            
            valueLabel.leadingAnchor.constraint(equalTo: keyLabel.trailingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setValue(_ value: String) {
        valueLabel.stringValue = value
    }
}
