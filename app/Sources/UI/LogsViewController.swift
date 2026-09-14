import AppKit

public final class LogsViewController: NSViewController {
    private let logStore = LogStore.shared
    
    private let searchField = NSSearchField()
    private let levelSegmented = NSSegmentedControl(labels: ["All", "INFO", "SUCCESS", "WARN", "ERROR"], trackingMode: .selectOne, target: nil, action: nil)
    private var textView: NSTextView!
    private var updateTimer: Timer?
    private var lastLoggedCount = 0
    
    public override func loadView() {
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 880, height: 750))
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 800),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: 680)
        ])
        self.view = root
    }
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateLogs()
        
        // Update timer for streaming log output
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkLogsUpdated()
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    private func setupUI() {
        // Toolbar
        let toolbarView = NSView()
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbarView)
        
        searchField.placeholderString = "Filter log entries..."
        searchField.target = self
        searchField.action = #selector(handleFilterChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        
        levelSegmented.selectedSegment = 0
        levelSegmented.target = self
        levelSegmented.action = #selector(handleFilterChanged)
        levelSegmented.translatesAutoresizingMaskIntoConstraints = false
        
        let copyButton = NSButton(title: "Copy", target: self, action: #selector(handleCopy))
        copyButton.bezelStyle = .rounded
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        
        let clearButton = NSButton(title: "Clear", target: self, action: #selector(handleClear))
        clearButton.bezelStyle = .rounded
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        
        toolbarView.addSubview(searchField)
        toolbarView.addSubview(levelSegmented)
        toolbarView.addSubview(copyButton)
        toolbarView.addSubview(clearButton)
        
        // Text View for Logs
        let scrollView = NSTextView.scrollableTextView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        view.addSubview(scrollView)
        
        textView = scrollView.documentView as? NSTextView
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.85)
        
        NSLayoutConstraint.activate([
            toolbarView.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            toolbarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            toolbarView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            toolbarView.heightAnchor.constraint(equalToConstant: 32),
            
            searchField.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor),
            searchField.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 220),
            
            levelSegmented.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 12),
            levelSegmented.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            
            clearButton.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor),
            clearButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            
            copyButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            copyButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            
            scrollView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
    }
    
    private func checkLogsUpdated() {
        if logStore.items.count != lastLoggedCount {
            updateLogs()
        }
    }
    
    private func updateLogs() {
        lastLoggedCount = logStore.items.count
        
        let query = searchField.stringValue.lowercased()
        let selectedSeg = levelSegmented.selectedSegment
        
        let filtered = logStore.items.filter { item in
            let matchesQuery = query.isEmpty || item.message.lowercased().contains(query)
            let matchesLevel: Bool
            switch selectedSeg {
            case 1: matchesLevel = (item.level == .info)
            case 2: matchesLevel = (item.level == .success)
            case 3: matchesLevel = (item.level == .warning)
            case 4: matchesLevel = (item.level == .error)
            default: matchesLevel = true
            }
            return matchesQuery && matchesLevel
        }
        
        let attributed = NSMutableAttributedString()
        for item in filtered {
            let color: NSColor
            switch item.level {
            case .info: color = .systemCyan
            case .success: color = .systemGreen
            case .warning: color = .systemOrange
            case .error: color = .systemRed
            }
            
            let timeStr = "[\(item.formattedTime)] "
            let levelStr = "[\(item.level.rawValue)] "
            let msgStr = "\(item.message)\n"
            
            let timeAttr = NSAttributedString(string: timeStr, attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            ])
            let levelAttr = NSAttributedString(string: levelStr, attributes: [
                .foregroundColor: color,
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
            ])
            let msgAttr = NSAttributedString(string: msgStr, attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            ])
            
            attributed.append(timeAttr)
            attributed.append(levelAttr)
            attributed.append(msgAttr)
        }
        
        textView.textStorage?.setAttributedString(attributed)
        textView.scrollToEndOfDocument(nil)
    }
    
    @objc private func handleFilterChanged() {
        updateLogs()
    }
    
    @objc private func handleCopy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logStore.exportText(), forType: .string)
    }
    
    @objc private func handleClear() {
        logStore.clear()
        updateLogs()
    }
}
