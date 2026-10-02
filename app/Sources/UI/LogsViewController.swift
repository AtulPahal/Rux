import AppKit
import Combine

public final class LogsViewController: NSViewController {
    private let logStore = LogStore.shared
    private var cancellables = Set<AnyCancellable>()
    
    private let searchField = NSSearchField()
    private let levelSegmented = NSSegmentedControl(labels: ["All", "INFO", "SUCCESS", "WARN", "ERROR"], trackingMode: .selectOne, target: nil, action: nil)
    private let logCountLabel = NSTextField(labelWithString: "0 entries")
    private let copyButton = NSButton()
    private let clearButton = NSButton()
    
    private var textView: NSTextView!
    private var scrollView: NSScrollView!
    private var lastRenderedCount = 0
    private var currentFilterLevel: LogLevel? = nil
    private var currentSearchText: String = ""
    
    public override func loadView() {
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 1140, height: 750))
        root.autoresizingMask = [.width, .height]
        self.view = root
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        fullReloadLogs()
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
        
        logCountLabel.font = .systemFont(ofSize: 11)
        logCountLabel.textColor = .secondaryLabelColor
        logCountLabel.translatesAutoresizingMaskIntoConstraints = false
        
        copyButton.title = "Copy Logs"
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(handleCopy)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        
        clearButton.title = "Clear"
        clearButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(handleClear)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        
        toolbarView.addSubview(searchField)
        toolbarView.addSubview(levelSegmented)
        toolbarView.addSubview(logCountLabel)
        toolbarView.addSubview(copyButton)
        toolbarView.addSubview(clearButton)
        
        // Scrollable Text View
        scrollView = NSTextView.scrollableTextView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
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
            toolbarView.heightAnchor.constraint(equalToConstant: 30),
            
            searchField.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor),
            searchField.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 240),
            
            levelSegmented.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 12),
            levelSegmented.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            
            logCountLabel.leadingAnchor.constraint(equalTo: levelSegmented.trailingAnchor, constant: 12),
            logCountLabel.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            
            clearButton.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor),
            clearButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            
            copyButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            copyButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            
            scrollView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
        ])
    }
    
    private func bindViewModel() {
        logStore.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.handleNewLogs(items: items)
            }
            .store(in: &cancellables)
    }
    
    private func handleNewLogs(items: [LogItem]) {
        // If items were cleared or rolled over, do full reload
        if items.count < lastRenderedCount {
            fullReloadLogs()
            return
        }
        
        // If there's an active filter or search, do full reload
        if currentFilterLevel != nil || !currentSearchText.isEmpty {
            fullReloadLogs()
            return
        }
        
        // Append only new items
        let newItems = items.suffix(items.count - lastRenderedCount)
        guard !newItems.isEmpty else { return }
        
        let wasAtBottom = isScrolledToBottom()
        
        let attributed = NSMutableAttributedString()
        for item in newItems {
            attributed.append(formatLogItem(item))
        }
        
        if let storage = textView.textStorage {
            storage.append(attributed)
            lastRenderedCount = items.count
            logCountLabel.stringValue = "\(items.count) entries"
            
            if wasAtBottom {
                textView.scrollToEndOfDocument(nil)
            }
        }
    }
    
    private func fullReloadLogs() {
        let items = logStore.items
        let filter = currentFilterLevel
        let search = currentSearchText.lowercased()
        
        let filtered = items.filter { item in
            let matchesLevel = (filter == nil || item.level == filter)
            let matchesSearch = search.isEmpty || item.message.lowercased().contains(search) || item.level.rawValue.lowercased().contains(search)
            return matchesLevel && matchesSearch
        }
        
        let wasAtBottom = isScrolledToBottom()
        
        let result = NSMutableAttributedString()
        for item in filtered {
            result.append(formatLogItem(item))
        }
        
        if let storage = textView.textStorage {
            storage.setAttributedString(result)
            lastRenderedCount = items.count
            logCountLabel.stringValue = "\(filtered.count) entries"
            
            if wasAtBottom {
                textView.scrollToEndOfDocument(nil)
            }
        }
    }
    
    private func formatLogItem(_ item: LogItem) -> NSAttributedString {
        let line = NSMutableAttributedString()
        
        // Timestamp
        let timeAttr: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        ]
        line.append(NSAttributedString(string: "[\(item.formattedTime)] ", attributes: timeAttr))
        
        // Level Badge
        let levelColor: NSColor
        switch item.level {
        case .info: levelColor = .labelColor
        case .success: levelColor = .systemGreen
        case .warning: levelColor = .systemOrange
        case .error: levelColor = .systemRed
        }
        
        let levelAttr: [NSAttributedString.Key: Any] = [
            .foregroundColor: levelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        ]
        line.append(NSAttributedString(string: "[\(item.level.rawValue)] ", attributes: levelAttr))
        
        // Message
        let msgAttr: [NSAttributedString.Key: Any] = [
            .foregroundColor: levelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]
        line.append(NSAttributedString(string: "\(item.message)\n", attributes: msgAttr))
        
        return line
    }
    
    private func isScrolledToBottom() -> Bool {
        guard let docView = scrollView.documentView else { return true }
        let visibleRect = scrollView.documentVisibleRect
        return visibleRect.maxY >= (docView.bounds.maxY - 30)
    }
    
    // MARK: - Actions
    
    @objc private func handleFilterChanged() {
        switch levelSegmented.selectedSegment {
        case 1: currentFilterLevel = .info
        case 2: currentFilterLevel = .success
        case 3: currentFilterLevel = .warning
        case 4: currentFilterLevel = .error
        default: currentFilterLevel = nil
        }
        
        currentSearchText = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        fullReloadLogs()
    }
    
    @objc private func handleClear() {
        logStore.clear()
        fullReloadLogs()
    }
    
    @objc private func handleCopy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textView.string, forType: .string)
    }
}
