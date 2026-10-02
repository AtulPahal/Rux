import AppKit
import Combine

public final class DiagnosticsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let diagnostics = DiagnosticsRunner()
    private var cancellables = Set<AnyCancellable>()
    
    // Header & Summary Elements
    private let statusPill = StatusPillView(text: "Ready", color: .systemGray)
    private let summaryLabel = NSTextField(labelWithString: "Ready to execute Darwin Mach-O system diagnostic suite.")
    private let runButton = NSButton()
    private let exportButton = NSButton()
    private let progressIndicator = NSProgressIndicator()
    
    // Results Table
    private let tableView = NSTableView()
    
    public override func loadView() {
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 1140, height: 750))
        root.autoresizingMask = [.width, .height]
        self.view = root
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        diagnostics.runDiagnostics()
    }
    
    private func setupUI() {
        // Header Box
        let headerBox = NSBox()
        headerBox.boxType = .custom
        headerBox.borderWidth = 1
        headerBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.35)
        headerBox.cornerRadius = 10
        headerBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45)
        headerBox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerBox)
        
        let titleLabel = NSTextField(labelWithString: "Darwin Mach-O Diagnostics")
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBox.addSubview(titleLabel)
        
        let subLabel = NSTextField(labelWithString: "Verify Darwin kernel primitives: Mach VM allocation, task ports, symbol resolution & process inspection.")
        subLabel.font = .systemFont(ofSize: 11)
        subLabel.textColor = .secondaryLabelColor
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBox.addSubview(subLabel)
        
        statusPill.translatesAutoresizingMaskIntoConstraints = false
        headerBox.addSubview(statusPill)
        
        runButton.title = "Run Diagnostics"
        runButton.image = NSImage(systemSymbolName: "stethoscope", accessibilityDescription: nil)
        runButton.imagePosition = .imageLeading
        runButton.bezelStyle = .rounded
        runButton.contentTintColor = .controlAccentColor
        runButton.font = .systemFont(ofSize: 12, weight: .bold)
        runButton.target = self
        runButton.action = #selector(handleRunDiagnostics)
        runButton.translatesAutoresizingMaskIntoConstraints = false
        headerBox.addSubview(runButton)
        
        exportButton.title = "Export Report"
        exportButton.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        exportButton.imagePosition = .imageLeading
        exportButton.bezelStyle = .rounded
        exportButton.target = self
        exportButton.action = #selector(handleExportReport)
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        headerBox.addSubview(exportButton)
        
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        headerBox.addSubview(progressIndicator)
        
        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = .labelColor
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBox.addSubview(summaryLabel)
        
        // Table View for Test Results
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true
        view.addSubview(scrollView)
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 32
        tableView.usesAlternatingRowBackgroundColors = true
        
        let statusCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusCol.title = "Result"
        statusCol.width = 90
        tableView.addTableColumn(statusCol)
        
        let idCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("id"))
        idCol.title = "#"
        idCol.width = 40
        tableView.addTableColumn(idCol)
        
        let titleCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleCol.title = "Diagnostic Target & Kernel Primitive"
        titleCol.width = 380
        tableView.addTableColumn(titleCol)
        
        let detailsCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("details"))
        detailsCol.title = "Detailed Output & Status"
        detailsCol.width = 480
        tableView.addTableColumn(detailsCol)
        
        scrollView.documentView = tableView
        
        NSLayoutConstraint.activate([
            headerBox.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            headerBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            headerBox.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            headerBox.heightAnchor.constraint(equalToConstant: 92),
            
            titleLabel.topAnchor.constraint(equalTo: headerBox.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: headerBox.leadingAnchor, constant: 14),
            
            statusPill.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 10),
            statusPill.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            
            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            
            summaryLabel.topAnchor.constraint(equalTo: subLabel.bottomAnchor, constant: 8),
            summaryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            
            exportButton.trailingAnchor.constraint(equalTo: headerBox.trailingAnchor, constant: -14),
            exportButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            
            runButton.trailingAnchor.constraint(equalTo: exportButton.leadingAnchor, constant: -8),
            runButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            
            progressIndicator.trailingAnchor.constraint(equalTo: runButton.leadingAnchor, constant: -8),
            progressIndicator.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            
            scrollView.topAnchor.constraint(equalTo: headerBox.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
        ])
    }
    
    private func bindViewModel() {
        diagnostics.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRunning in
                self?.runButton.isEnabled = !isRunning
                if isRunning {
                    self?.progressIndicator.startAnimation(nil)
                    self?.statusPill.update(text: "Running...", color: .systemOrange)
                } else {
                    self?.progressIndicator.stopAnimation(nil)
                }
            }
            .store(in: &cancellables)
        
        diagnostics.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)
        
        diagnostics.$summary
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sum in
                self?.summaryLabel.stringValue = sum
            }
            .store(in: &cancellables)
        
        diagnostics.$allPassed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] allPassed in
                guard let self = self, let passed = allPassed else { return }
                if passed {
                    self.statusPill.update(text: "All Passed", color: .systemGreen)
                } else {
                    self.statusPill.update(text: "Failed", color: .systemRed)
                }
            }
            .store(in: &cancellables)
    }
    
    @objc private func handleRunDiagnostics() {
        diagnostics.runDiagnostics()
    }
    
    @objc private func handleExportReport() {
        let lines = diagnostics.items.map { "[\($0.passed ? "PASS" : "FAIL")] #\($0.id): \($0.title) -> \($0.details)" }
        let report = """
        === Rux Darwin Mach-O Diagnostics Report ===
        Summary: \(diagnostics.summary)
        Total Tests: \(diagnostics.items.count)
        
        \(lines.joined(separator: "\n"))
        """
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        
        let alert = NSAlert()
        alert.messageText = "Diagnostic Report Copied"
        alert.informativeText = "The full diagnostic report has been copied to your clipboard."
        alert.runModal()
    }
    
    // MARK: - NSTableViewDataSource & Delegate
    
    public func numberOfRows(in tableView: NSTableView) -> Int {
        diagnostics.items.count
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0 && row < diagnostics.items.count else { return nil }
        let item = diagnostics.items[row]
        let identifier = tableColumn?.identifier.rawValue ?? ""
        
        switch identifier {
        case "status":
            let pill = StatusPillView(
                text: item.passed ? "PASS" : "FAIL",
                color: item.passed ? .systemGreen : .systemRed
            )
            return pill
            
        case "id":
            let cell = NSTextField(labelWithString: "#\(item.id)")
            cell.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.textColor = .secondaryLabelColor
            return cell
            
        case "title":
            let cell = NSTextField(labelWithString: item.title)
            cell.font = .systemFont(ofSize: 12, weight: .medium)
            return cell
            
        case "details":
            let cell = NSTextField(labelWithString: item.details)
            cell.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.textColor = item.passed ? .labelColor : .systemRed
            return cell
            
        default:
            return nil
        }
    }
}
