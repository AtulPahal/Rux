import AppKit

public final class DiagnosticsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let diagnostics = DiagnosticsRunner()
    
    private let summaryBox = NSBox()
    private let summaryLabel = NSTextField(labelWithString: "Ready to run Darwin Mach-O diagnostics.")
    private let runButton = NSButton()
    private let progressIndicator = NSProgressIndicator()
    private let tableView = NSTableView()
    
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
    }
    
    private func setupUI() {
        // Header
        let titleLabel = NSTextField(labelWithString: "Darwin System Diagnostics")
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let subLabel = NSTextField(labelWithString: "Verify Darwin Mach kernel APIs, memory management, and shared cache symbol resolution.")
        subLabel.font = .systemFont(ofSize: 12)
        subLabel.textColor = .secondaryLabelColor
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        
        runButton.title = "  Run Diagnostic Suite"
        runButton.image = NSImage(systemSymbolName: "stethoscope", accessibilityDescription: nil)
        runButton.bezelStyle = .regularSquare
        runButton.wantsLayer = true
        runButton.layer?.backgroundColor = NSColor.systemCyan.cgColor
        runButton.layer?.cornerRadius = 6
        runButton.contentTintColor = .black
        runButton.font = .systemFont(ofSize: 13, weight: .bold)
        runButton.target = self
        runButton.action = #selector(handleRunDiagnostics)
        runButton.translatesAutoresizingMaskIntoConstraints = false
        
        progressIndicator.style = .spinning
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        // Summary Box
        summaryBox.boxType = .custom
        summaryBox.borderWidth = 1
        summaryBox.borderColor = .separatorColor
        summaryBox.cornerRadius = 8
        summaryBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4)
        summaryBox.translatesAutoresizingMaskIntoConstraints = false
        
        summaryLabel.font = .systemFont(ofSize: 13, weight: .medium)
        summaryLabel.lineBreakMode = .byWordWrapping
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryBox.addSubview(summaryLabel)
        
        NSLayoutConstraint.activate([
            summaryLabel.topAnchor.constraint(equalTo: summaryBox.topAnchor, constant: 12),
            summaryLabel.leadingAnchor.constraint(equalTo: summaryBox.leadingAnchor, constant: 14),
            summaryLabel.trailingAnchor.constraint(equalTo: summaryBox.trailingAnchor, constant: -14),
            summaryLabel.bottomAnchor.constraint(equalTo: summaryBox.bottomAnchor, constant: -12)
        ])
        
        // Table View for Tests
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 36
        tableView.usesAlternatingRowBackgroundColors = true
        
        let statusCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusCol.title = "Result"
        statusCol.width = 80
        tableView.addTableColumn(statusCol)
        
        let titleCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleCol.title = "Diagnostic Test"
        titleCol.width = 280
        tableView.addTableColumn(titleCol)
        
        let detailsCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("details"))
        detailsCol.title = "Details"
        detailsCol.width = 300
        tableView.addTableColumn(detailsCol)
        
        scrollView.documentView = tableView
        
        view.addSubview(titleLabel)
        view.addSubview(subLabel)
        view.addSubview(runButton)
        view.addSubview(progressIndicator)
        view.addSubview(summaryBox)
        view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            
            runButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            runButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            runButton.widthAnchor.constraint(equalToConstant: 190),
            runButton.heightAnchor.constraint(equalToConstant: 32),
            
            progressIndicator.trailingAnchor.constraint(equalTo: runButton.leadingAnchor, constant: -10),
            progressIndicator.centerYAnchor.constraint(equalTo: runButton.centerYAnchor),
            
            summaryBox.topAnchor.constraint(equalTo: subLabel.bottomAnchor, constant: 14),
            summaryBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            summaryBox.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            scrollView.topAnchor.constraint(equalTo: summaryBox.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }
    
    @objc private func handleRunDiagnostics() {
        runButton.isEnabled = false
        progressIndicator.startAnimation(nil)
        summaryLabel.stringValue = "Running diagnostic test suite..."
        summaryLabel.textColor = .labelColor
        summaryBox.borderColor = .separatorColor
        summaryBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4)
        
        diagnostics.runDiagnostics()
        
        // Poll for completion
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                if !self.diagnostics.isRunning {
                    timer.invalidate()
                    self.runButton.isEnabled = true
                    self.progressIndicator.stopAnimation(nil)
                    self.summaryLabel.stringValue = self.diagnostics.summary
                    
                    if let allPassed = self.diagnostics.allPassed {
                        if allPassed {
                            self.summaryLabel.textColor = .systemGreen
                            self.summaryBox.borderColor = .systemGreen
                            self.summaryBox.fillColor = NSColor.systemGreen.withAlphaComponent(0.1)
                        } else {
                            self.summaryLabel.textColor = .systemRed
                            self.summaryBox.borderColor = .systemRed
                            self.summaryBox.fillColor = NSColor.systemRed.withAlphaComponent(0.1)
                        }
                    }
                    
                    self.tableView.reloadData()
                }
            }
        }
    }
    
    // MARK: - NSTableViewDataSource & Delegate
    
    public func numberOfRows(in tableView: NSTableView) -> Int {
        diagnostics.items.count
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0 && row < diagnostics.items.count else { return nil }
        let item = diagnostics.items[row]
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
                tf.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 6),
                tf.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -6),
                tf.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
            ])
        }
        
        let tf = cell?.textField
        switch colId {
        case "status":
            tf?.stringValue = item.passed ? "✓ PASS" : "✕ FAIL"
            tf?.font = .systemFont(ofSize: 12, weight: .bold)
            tf?.textColor = item.passed ? .systemGreen : .systemRed
        case "title":
            tf?.stringValue = item.title
            tf?.font = .systemFont(ofSize: 12, weight: .medium)
            tf?.textColor = .labelColor
        case "details":
            tf?.stringValue = item.details
            tf?.font = .systemFont(ofSize: 11)
            tf?.textColor = .secondaryLabelColor
        default:
            break
        }
        
        return cell
    }
}
