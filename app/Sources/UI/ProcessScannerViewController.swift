import AppKit

public final class ProcessScannerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    public var onSelectProcess: ((Int32, String, String) -> Void)?
    
    private let scanner = ProcessScanner()
    private var displayedProcesses: [ProcessItem] = []
    
    private let searchField = NSSearchField()
    private let archSegmented = NSSegmentedControl(labels: ["All Archs", "ARM64", "x86_64"], trackingMode: .selectOne, target: nil, action: nil)
    private let refreshButton = NSButton()
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "Loading Darwin processes...")
    private let targetButton = NSButton()
    
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
        loadData()
    }
    
    private func setupUI() {
        // Top Toolbar
        let toolbarView = NSView()
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbarView)
        
        searchField.placeholderString = "Search running processes by name, PID, or path..."
        searchField.target = self
        searchField.action = #selector(handleSearchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        
        archSegmented.selectedSegment = 0
        archSegmented.target = self
        archSegmented.action = #selector(handleArchChanged)
        archSegmented.translatesAutoresizingMaskIntoConstraints = false
        
        refreshButton.title = "Refresh"
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(handleRefresh)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        
        toolbarView.addSubview(searchField)
        toolbarView.addSubview(archSegmented)
        toolbarView.addSubview(refreshButton)
        
        // Table View
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        view.addSubview(scrollView)
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(handleRowDoubleClicked)
        tableView.target = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.rowHeight = 24
        
        let pidCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pid"))
        pidCol.title = "PID"
        pidCol.width = 65
        tableView.addTableColumn(pidCol)
        
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Process Name"
        nameCol.width = 170
        tableView.addTableColumn(nameCol)
        
        let archCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("arch"))
        archCol.title = "Arch"
        archCol.width = 75
        tableView.addTableColumn(archCol)
        
        let pathCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        pathCol.title = "Executable Path"
        pathCol.width = 380
        tableView.addTableColumn(pathCol)
        
        scrollView.documentView = tableView
        
        // Bottom Bar
        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)
        
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        targetButton.title = "Target Selected Process"
        targetButton.image = NSImage(systemSymbolName: "scope", accessibilityDescription: nil)
        targetButton.bezelStyle = .rounded
        targetButton.target = self
        targetButton.action = #selector(handleTargetSelected)
        targetButton.translatesAutoresizingMaskIntoConstraints = false
        
        bottomBar.addSubview(statusLabel)
        bottomBar.addSubview(targetButton)
        
        NSLayoutConstraint.activate([
            toolbarView.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            toolbarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            toolbarView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            toolbarView.heightAnchor.constraint(equalToConstant: 32),
            
            searchField.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor),
            searchField.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: archSegmented.leadingAnchor, constant: -12),
            
            archSegmented.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            archSegmented.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -12),
            
            refreshButton.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor),
            refreshButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            
            scrollView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -10),
            
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            bottomBar.heightAnchor.constraint(equalToConstant: 28),
            
            statusLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            
            targetButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            targetButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor)
        ])
    }
    
    private func loadData() {
        scanner.refresh()
        
        // Wait for scanner to populate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateFilter()
        }
    }
    
    private func updateFilter() {
        let query = searchField.stringValue.lowercased()
        let selectedSegment = archSegmented.selectedSegment
        
        displayedProcesses = scanner.processes.filter { proc in
            let matchesQuery: Bool
            if query.isEmpty {
                matchesQuery = true
            } else {
                matchesQuery = "\(proc.pid)".contains(query)
                    || proc.name.lowercased().contains(query)
                    || (proc.path?.lowercased().contains(query) ?? false)
            }
            
            let matchesArch: Bool
            if selectedSegment == 1 {
                matchesArch = (proc.arch == .arm64)
            } else if selectedSegment == 2 {
                matchesArch = (proc.arch == .x86_64)
            } else {
                matchesArch = true
            }
            
            return matchesQuery && matchesArch
        }
        
        tableView.reloadData()
        statusLabel.stringValue = "Showing \(displayedProcesses.count) of \(scanner.processes.count) active Darwin processes"
    }
    
    @objc private func handleSearchChanged() {
        updateFilter()
    }
    
    @objc private func handleArchChanged() {
        updateFilter()
    }
    
    @objc private func handleRefresh() {
        statusLabel.stringValue = "Refreshing Darwin processes..."
        scanner.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateFilter()
        }
    }
    
    @objc private func handleRowDoubleClicked() {
        handleTargetSelected()
    }
    
    @objc private func handleTargetSelected() {
        let row = tableView.selectedRow
        guard row >= 0 && row < displayedProcesses.count else { return }
        let selected = displayedProcesses[row]
        onSelectProcess?(selected.pid, selected.name, selected.arch.rawValue)
    }
    
    // MARK: - NSTableViewDataSource & Delegate
    
    public func numberOfRows(in tableView: NSTableView) -> Int {
        displayedProcesses.count
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0 && row < displayedProcesses.count else { return nil }
        let proc = displayedProcesses[row]
        let colId = tableColumn?.identifier.rawValue ?? ""
        
        let cellId = NSUserInterfaceItemIdentifier("cell_\(colId)")
        var cell = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTableCellView
        
        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = cellId
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.isBordered = false
            tf.backgroundColor = .clear
            cell?.addSubview(tf)
            cell?.textField = tf
            
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
            ])
        }
        
        let tf = cell?.textField
        switch colId {
        case "pid":
            tf?.stringValue = "\(proc.pid)"
            tf?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            tf?.textColor = .labelColor
        case "name":
            tf?.stringValue = proc.name
            tf?.font = .systemFont(ofSize: 12, weight: .semibold)
            tf?.textColor = .labelColor
        case "arch":
            tf?.stringValue = proc.arch.rawValue.uppercased()
            tf?.font = .systemFont(ofSize: 11, weight: .bold)
            tf?.textColor = (proc.arch == .arm64) ? .systemPurple : .systemCyan
        case "path":
            tf?.stringValue = proc.displayPath
            tf?.font = .systemFont(ofSize: 11)
            tf?.textColor = .secondaryLabelColor
        default:
            break
        }
        
        return cell
    }
}
