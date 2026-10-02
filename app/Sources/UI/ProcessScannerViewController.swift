import AppKit
import Combine

public final class ProcessScannerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    public var onSelectProcess: ((Int32, String, String) -> Void)?
    
    private let scanner = ProcessScanner()
    private var displayedProcesses: [ProcessItem] = []
    private var selectedProcess: ProcessItem? = nil
    
    // Loaded modules cache for the inspector
    private var cachedModules: [LoadedModule] = []
    private var displayedModules: [LoadedModule] = []
    private var cachedSecurity: ProcessSecurityInfo? = nil
    private var cachedResources: ProcessResourceUsage? = nil
    
    // UI Elements - Left Master View
    private let searchField = NSSearchField()
    private let archSegmented = NSSegmentedControl(labels: ["All", "ARM64", "x86_64"], trackingMode: .selectOne, target: nil, action: nil)
    private let refreshButton = NSButton()
    private let refreshSpinner = NSProgressIndicator()
    private let processTableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "Scanning Darwin processes...")
    
    // UI Elements - Right Inspector View
    private let inspectorContainer = NSView()
    private let inspectorIconView = NSImageView()
    private let inspectorTitleLabel = NSTextField(labelWithString: "No Process Selected")
    private let inspectorSubLabel = NSTextField(labelWithString: "Select a process from the list to inspect security and loaded modules.")
    private let targetInInjectorButton = NSButton()
    
    private let inspectorTabs = NSSegmentedControl(labels: ["Security & Telemetry", "Loaded Modules"], trackingMode: .selectOne, target: nil, action: nil)
    
    // Inspector Subviews
    private let securityView = FlippedView()
    private let modulesView = FlippedView()
    
    // Security Key-Value Rows
    private let pidRow = KeyValueRowView(key: "Process PID:", value: "-", isMonospaced: true)
    private let ppidRow = KeyValueRowView(key: "Parent PID:", value: "-", isMonospaced: true)
    private let userRow = KeyValueRowView(key: "User / UID:", value: "-")
    private let memoryRow = KeyValueRowView(key: "Resident Memory:", value: "-")
    private let uptimeRow = KeyValueRowView(key: "Process Uptime:", value: "-")
    private let threadsRow = KeyValueRowView(key: "Active Threads:", value: "-")
    private let teamIdRow = KeyValueRowView(key: "Team Identifier:", value: "-")
    private let cdHashRow = KeyValueRowView(key: "Code Directory Hash:", value: "-", isMonospaced: true)
    
    // Security Badges
    private let hardenedBadge = StatusPillView(text: "Hardened Runtime", color: .systemPurple)
    private let libraryValidationBadge = StatusPillView(text: "Library Validation", color: .systemOrange)
    private let debuggableBadge = StatusPillView(text: "Debuggable", color: .systemGreen)
    private let restrictedBadge = StatusPillView(text: "Restricted", color: .systemRed)
    
    // Injection Feasibility Banner
    private let feasibilityBox = NSBox()
    private let feasibilityLabel = NSTextField(labelWithString: "")
    
    // Modules Table
    private let moduleSearchField = NSSearchField()
    private let modulesTableView = NSTableView()
    private let moduleCountLabel = NSTextField(labelWithString: "0 modules mapped")
    
    // Cancellables
    private var cancellables = Set<AnyCancellable>()
    
    public override func loadView() {
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 1140, height: 750))
        root.autoresizingMask = [.width, .height]
        self.view = root
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        loadData()
    }
    
    private func setupUI() {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)
        
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // 1. Left Master Pane
        let masterPane = NSView()
        masterPane.translatesAutoresizingMaskIntoConstraints = false
        setupMasterPane(in: masterPane)
        splitView.addSubview(masterPane)
        
        // 2. Right Detail Inspector Pane
        inspectorContainer.translatesAutoresizingMaskIntoConstraints = false
        setupInspectorPane(in: inspectorContainer)
        splitView.addSubview(inspectorContainer)
        
        splitView.setPosition(680, ofDividerAt: 0)
    }
    
    private func setupMasterPane(in container: NSView) {
        // Toolbar
        let toolbarView = NSView()
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbarView)
        
        searchField.placeholderString = "Filter processes by name, PID, or bundle ID..."
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
        
        refreshSpinner.style = .spinning
        refreshSpinner.controlSize = .small
        refreshSpinner.isDisplayedWhenStopped = false
        refreshSpinner.translatesAutoresizingMaskIntoConstraints = false
        
        toolbarView.addSubview(searchField)
        toolbarView.addSubview(archSegmented)
        toolbarView.addSubview(refreshButton)
        toolbarView.addSubview(refreshSpinner)
        
        // Table View
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        container.addSubview(scrollView)
        
        processTableView.dataSource = self
        processTableView.delegate = self
        processTableView.doubleAction = #selector(handleRowDoubleClicked)
        processTableView.target = self
        processTableView.usesAlternatingRowBackgroundColors = true
        processTableView.allowsMultipleSelection = false
        processTableView.rowHeight = 28
        
        let iconCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("icon"))
        iconCol.title = ""
        iconCol.width = 24
        processTableView.addTableColumn(iconCol)
        
        let pidCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pid"))
        pidCol.title = "PID"
        pidCol.width = 65
        processTableView.addTableColumn(pidCol)
        
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Process Name"
        nameCol.width = 200
        processTableView.addTableColumn(nameCol)
        
        let archCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("arch"))
        archCol.title = "Arch"
        archCol.width = 95
        processTableView.addTableColumn(archCol)
        
        let secCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("security"))
        secCol.title = "Security"
        secCol.width = 125
        processTableView.addTableColumn(secCol)
        let pathCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        pathCol.title = "Executable Path"
        pathCol.width = 300
        processTableView.addTableColumn(pathCol)
        
        scrollView.documentView = processTableView
        
        // Bottom Status Bar
        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bottomBar)
        
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(statusLabel)
        
        NSLayoutConstraint.activate([
            toolbarView.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            toolbarView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            toolbarView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            toolbarView.heightAnchor.constraint(equalToConstant: 30),
            
            searchField.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor),
            searchField.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: archSegmented.leadingAnchor, constant: -10),
            
            archSegmented.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            archSegmented.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -10),
            
            refreshButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: refreshSpinner.leadingAnchor, constant: -6),
            
            refreshSpinner.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            refreshSpinner.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor),
            
            scrollView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),
            
            bottomBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            bottomBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            bottomBar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            bottomBar.heightAnchor.constraint(equalToConstant: 20),
            
            statusLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor)
        ])
    }
    
    private func setupInspectorPane(in container: NSView) {
        // Header
        inspectorIconView.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        inspectorIconView.contentTintColor = .controlAccentColor
        inspectorIconView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inspectorIconView)
        
        inspectorTitleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        inspectorTitleLabel.lineBreakMode = .byTruncatingTail
        inspectorTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inspectorTitleLabel)
        
        inspectorSubLabel.font = .systemFont(ofSize: 11, weight: .regular)
        inspectorSubLabel.textColor = .secondaryLabelColor
        inspectorSubLabel.lineBreakMode = .byTruncatingTail
        inspectorSubLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inspectorSubLabel)
        
        targetInInjectorButton.title = "Target in Injector"
        targetInInjectorButton.image = NSImage(systemSymbolName: "syringe", accessibilityDescription: nil)
        targetInInjectorButton.bezelStyle = .rounded
        targetInInjectorButton.contentTintColor = .controlAccentColor
        targetInInjectorButton.target = self
        targetInInjectorButton.action = #selector(handleTargetSelected)
        targetInInjectorButton.isEnabled = false
        targetInInjectorButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(targetInInjectorButton)
        
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(divider)
        
        inspectorTabs.selectedSegment = 0
        inspectorTabs.target = self
        inspectorTabs.action = #selector(handleInspectorTabChanged)
        inspectorTabs.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inspectorTabs)
        
        // Security View Setup
        securityView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(securityView)
        setupSecurityInspector(in: securityView)
        
        // Modules View Setup
        modulesView.translatesAutoresizingMaskIntoConstraints = false
        modulesView.isHidden = true
        container.addSubview(modulesView)
        setupModulesInspector(in: modulesView)
        
        NSLayoutConstraint.activate([
            inspectorIconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            inspectorIconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            inspectorIconView.widthAnchor.constraint(equalToConstant: 28),
            inspectorIconView.heightAnchor.constraint(equalToConstant: 28),
            
            inspectorTitleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            inspectorTitleLabel.leadingAnchor.constraint(equalTo: inspectorIconView.trailingAnchor, constant: 10),
            inspectorTitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            
            inspectorSubLabel.topAnchor.constraint(equalTo: inspectorTitleLabel.bottomAnchor, constant: 2),
            inspectorSubLabel.leadingAnchor.constraint(equalTo: inspectorTitleLabel.leadingAnchor),
            inspectorSubLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            
            targetInInjectorButton.topAnchor.constraint(equalTo: inspectorSubLabel.bottomAnchor, constant: 10),
            targetInInjectorButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            targetInInjectorButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            
            divider.topAnchor.constraint(equalTo: targetInInjectorButton.bottomAnchor, constant: 10),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            divider.heightAnchor.constraint(equalToConstant: 1),
            
            inspectorTabs.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),
            inspectorTabs.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            inspectorTabs.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            
            securityView.topAnchor.constraint(equalTo: inspectorTabs.bottomAnchor, constant: 10),
            securityView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            securityView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            securityView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            
            modulesView.topAnchor.constraint(equalTo: inspectorTabs.bottomAnchor, constant: 10),
            modulesView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            modulesView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            modulesView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
    }
    
    private func setupSecurityInspector(in container: NSView) {
        let badgeStack = NSStackView(views: [hardenedBadge, libraryValidationBadge, debuggableBadge, restrictedBadge])
        badgeStack.orientation = .horizontal
        badgeStack.spacing = 6
        badgeStack.distribution = .fillProportionally
        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(badgeStack)
        
        let metricsGroup = GroupSectionView(title: "Process Runtime Metrics", subtitle: "Kernel task info & memory usage", iconName: "chart.bar.xaxis")
        container.addSubview(metricsGroup)
        
        let mStack = NSStackView(views: [pidRow, ppidRow, userRow, memoryRow, uptimeRow, threadsRow])
        mStack.orientation = .vertical
        mStack.spacing = 4
        mStack.alignment = .leading
        mStack.translatesAutoresizingMaskIntoConstraints = false
        metricsGroup.contentView.addSubview(mStack)
        
        let secGroup = GroupSectionView(title: "Darwin Code Signing & Security", subtitle: "Kernel csops security flags", iconName: "shield.checkerboard")
        container.addSubview(secGroup)
        
        let sStack = NSStackView(views: [teamIdRow, cdHashRow])
        sStack.orientation = .vertical
        sStack.spacing = 4
        sStack.alignment = .leading
        sStack.translatesAutoresizingMaskIntoConstraints = false
        secGroup.contentView.addSubview(sStack)
        
        // Feasibility Box
        feasibilityBox.boxType = .custom
        feasibilityBox.borderWidth = 1
        feasibilityBox.cornerRadius = 8
        feasibilityBox.translatesAutoresizingMaskIntoConstraints = false
        feasibilityBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4)
        feasibilityBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.3)
        container.addSubview(feasibilityBox)
        
        feasibilityLabel.font = .systemFont(ofSize: 11, weight: .medium)
        feasibilityLabel.lineBreakMode = .byWordWrapping
        feasibilityLabel.translatesAutoresizingMaskIntoConstraints = false
        feasibilityBox.addSubview(feasibilityLabel)
        
        NSLayoutConstraint.activate([
            badgeStack.topAnchor.constraint(equalTo: container.topAnchor),
            badgeStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            badgeStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            metricsGroup.topAnchor.constraint(equalTo: badgeStack.bottomAnchor, constant: 10),
            metricsGroup.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            metricsGroup.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            mStack.topAnchor.constraint(equalTo: metricsGroup.contentView.topAnchor),
            mStack.leadingAnchor.constraint(equalTo: metricsGroup.contentView.leadingAnchor),
            mStack.trailingAnchor.constraint(equalTo: metricsGroup.contentView.trailingAnchor),
            mStack.bottomAnchor.constraint(equalTo: metricsGroup.contentView.bottomAnchor),
            
            secGroup.topAnchor.constraint(equalTo: metricsGroup.bottomAnchor, constant: 10),
            secGroup.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            secGroup.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            sStack.topAnchor.constraint(equalTo: secGroup.contentView.topAnchor),
            sStack.leadingAnchor.constraint(equalTo: secGroup.contentView.leadingAnchor),
            sStack.trailingAnchor.constraint(equalTo: secGroup.contentView.trailingAnchor),
            sStack.bottomAnchor.constraint(equalTo: secGroup.contentView.bottomAnchor),
            
            feasibilityBox.topAnchor.constraint(equalTo: secGroup.bottomAnchor, constant: 10),
            feasibilityBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            feasibilityBox.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            feasibilityBox.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            
            feasibilityLabel.topAnchor.constraint(equalTo: feasibilityBox.topAnchor, constant: 8),
            feasibilityLabel.leadingAnchor.constraint(equalTo: feasibilityBox.leadingAnchor, constant: 10),
            feasibilityLabel.trailingAnchor.constraint(equalTo: feasibilityBox.trailingAnchor, constant: -10),
            feasibilityLabel.bottomAnchor.constraint(equalTo: feasibilityBox.bottomAnchor, constant: -8)
        ])
    }
    
    private func setupModulesInspector(in container: NSView) {
        moduleSearchField.placeholderString = "Filter loaded modules by name or path..."
        moduleSearchField.target = self
        moduleSearchField.action = #selector(handleModuleSearchChanged)
        moduleSearchField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(moduleSearchField)
        
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        container.addSubview(scrollView)
        
        modulesTableView.dataSource = self
        modulesTableView.delegate = self
        modulesTableView.rowHeight = 22
        modulesTableView.usesAlternatingRowBackgroundColors = true
        
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mod_name"))
        nameCol.title = "Module / Dynamic Library"
        nameCol.width = 180
        modulesTableView.addTableColumn(nameCol)
        
        let addrCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mod_addr"))
        addrCol.title = "Base Address"
        addrCol.width = 120
        modulesTableView.addTableColumn(addrCol)
        
        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mod_size"))
        sizeCol.title = "Mapped Size"
        sizeCol.width = 80
        modulesTableView.addTableColumn(sizeCol)
        
        scrollView.documentView = modulesTableView
        
        moduleCountLabel.font = .systemFont(ofSize: 11)
        moduleCountLabel.textColor = .secondaryLabelColor
        moduleCountLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(moduleCountLabel)
        
        NSLayoutConstraint.activate([
            moduleSearchField.topAnchor.constraint(equalTo: container.topAnchor),
            moduleSearchField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            moduleSearchField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            scrollView.topAnchor.constraint(equalTo: moduleSearchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: moduleCountLabel.topAnchor, constant: -6),
            
            moduleCountLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            moduleCountLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            moduleCountLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
    
    private func bindViewModel() {
        scanner.$processes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFilter()
            }
            .store(in: &cancellables)
        
        scanner.$isScanning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isScanning in
                if isScanning {
                    self?.refreshSpinner.startAnimation(nil)
                    self?.statusLabel.stringValue = "Scanning Darwin processes..."
                } else {
                    self?.refreshSpinner.stopAnimation(nil)
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadData() {
        scanner.refresh()
    }
    
    private func updateFilter() {
        let search = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let archFilter = archSegmented.selectedSegment
        
        displayedProcesses = scanner.processes.filter { proc in
            let matchesSearch: Bool
            if search.isEmpty {
                matchesSearch = true
            } else {
                matchesSearch = proc.name.lowercased().contains(search) ||
                                "\(proc.pid)".contains(search) ||
                                (proc.path?.lowercased().contains(search) ?? false) ||
                                (proc.bundleIdentifier?.lowercased().contains(search) ?? false)
            }
            
            let matchesArch: Bool
            switch archFilter {
            case 1: matchesArch = (proc.arch == .arm64)
            case 2: matchesArch = (proc.arch == .x86_64)
            default: matchesArch = true
            }
            
            return matchesSearch && matchesArch
        }
        
        processTableView.reloadData()
        statusLabel.stringValue = "Showing \(displayedProcesses.count) of \(scanner.processes.count) active Darwin processes"
        
        if selectedProcess == nil, let first = displayedProcesses.first {
            inspectProcess(first)
            processTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }
    
    // MARK: - Actions
    
    @objc private func handleSearchChanged() {
        updateFilter()
    }
    
    @objc private func handleArchChanged() {
        updateFilter()
    }
    
    @objc private func handleRefresh() {
        scanner.refresh()
    }
    
    @objc private func handleRowDoubleClicked() {
        let row = processTableView.clickedRow
        guard row >= 0 && row < displayedProcesses.count else { return }
        let proc = displayedProcesses[row]
        onSelectProcess?(proc.pid, proc.name, proc.arch.rawValue)
    }
    
    @objc private func handleTargetSelected() {
        guard let proc = selectedProcess else { return }
        onSelectProcess?(proc.pid, proc.name, proc.arch.rawValue)
    }
    
    @objc private func handleInspectorTabChanged() {
        let isModules = (inspectorTabs.selectedSegment == 1)
        securityView.isHidden = isModules
        modulesView.isHidden = !isModules
    }
    
    @objc private func handleModuleSearchChanged() {
        let search = moduleSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if search.isEmpty {
            displayedModules = cachedModules
        } else {
            displayedModules = cachedModules.filter {
                $0.name.lowercased().contains(search) || $0.path.lowercased().contains(search)
            }
        }
        modulesTableView.reloadData()
        moduleCountLabel.stringValue = "Showing \(displayedModules.count) of \(cachedModules.count) mapped modules"
    }
    
    private func inspectProcess(_ proc: ProcessItem) {
        selectedProcess = proc
        targetInInjectorButton.isEnabled = true
        
        inspectorTitleLabel.stringValue = proc.name
        inspectorSubLabel.stringValue = proc.bundleIdentifier ?? proc.displayPath
        
        if let app = NSRunningApplication(processIdentifier: proc.pid), let icon = app.icon {
            inspectorIconView.image = icon
        } else {
            inspectorIconView.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        }
        
        pidRow.setValue("\(proc.pid)")
        
        // Deep Fetch Security & Resources asynchronously
        Task.detached(priority: .userInitiated) {
            let sec = ProcessInspection.fetchSecurity(pid: proc.pid)
            let res = ProcessInspection.fetchResources(pid: proc.pid)
            let mods = ProcessInspection.enumerateModules(pid: proc.pid)
            
            await MainActor.run {
                guard self.selectedProcess?.pid == proc.pid else { return }
                self.cachedSecurity = sec
                self.cachedResources = res
                self.cachedModules = mods
                self.displayedModules = mods
                
                self.updateInspectorUI(proc: proc, sec: sec, res: res, mods: mods)
            }
        }
    }
    
    private func updateInspectorUI(
        proc: ProcessItem,
        sec: ProcessSecurityInfo?,
        res: ProcessResourceUsage?,
        mods: [LoadedModule]
    ) {
        if let res = res {
            ppidRow.setValue("\(res.parentPid)")
            userRow.setValue(res.username)
            memoryRow.setValue("\(res.formattedRss) (Virtual: \(res.formattedVirtualSize))")
            uptimeRow.setValue(res.formattedUptime)
            threadsRow.setValue("\(res.threadCount)")
        } else {
            ppidRow.setValue("-")
            userRow.setValue("-")
            memoryRow.setValue("-")
            uptimeRow.setValue("-")
            threadsRow.setValue("-")
        }
        
        if let sec = sec {
            teamIdRow.setValue(sec.teamIdentifier ?? "Ad-Hoc / None")
            cdHashRow.setValue(sec.cdHash ?? "-")
            
            hardenedBadge.update(text: "Hardened Runtime", color: sec.isHardenedRuntime ? .systemPurple : .systemGray)
            libraryValidationBadge.update(text: "Library Validation", color: sec.requiresLibraryValidation ? .systemOrange : .systemGray)
            debuggableBadge.update(text: "Debuggable", color: sec.hasGetTaskAllow ? .systemGreen : .systemGray)
            restrictedBadge.update(text: "Restricted", color: sec.isRestricted ? .systemRed : .systemGray)
            
            if sec.requiresLibraryValidation && !sec.hasGetTaskAllow {
                feasibilityLabel.stringValue = "⚠️ Injection Alert: Target enforces Library Validation (CS_REQUIRE_LV). Injection of third-party dylibs will be rejected by the kernel."
                feasibilityBox.borderColor = NSColor.systemOrange.withAlphaComponent(0.6)
                feasibilityLabel.textColor = .systemOrange
            } else if sec.isHardenedRuntime && !sec.hasGetTaskAllow {
                feasibilityLabel.stringValue = "ℹ️ Target has Hardened Runtime enabled. Root administrator privileges will be required to acquire task port."
                feasibilityBox.borderColor = NSColor.systemPurple.withAlphaComponent(0.6)
                feasibilityLabel.textColor = .systemPurple
            } else if sec.hasGetTaskAllow {
                feasibilityLabel.stringValue = "✓ Debuggable Target: Has get-task-allow entitlement. Can inject without root privileges."
                feasibilityBox.borderColor = NSColor.systemGreen.withAlphaComponent(0.6)
                feasibilityLabel.textColor = .systemGreen
            } else {
                feasibilityLabel.stringValue = "Ready for injection. Standard Darwin security flags."
                feasibilityBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.3)
                feasibilityLabel.textColor = .secondaryLabelColor
            }
        } else {
            teamIdRow.setValue("-")
            cdHashRow.setValue("-")
            hardenedBadge.update(text: "Hardened Runtime", color: .systemGray)
            libraryValidationBadge.update(text: "Library Validation", color: .systemGray)
            debuggableBadge.update(text: "Debuggable", color: .systemGray)
            restrictedBadge.update(text: "Restricted", color: .systemGray)
            feasibilityLabel.stringValue = "Standard process inspection."
            feasibilityBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.3)
            feasibilityLabel.textColor = .secondaryLabelColor
        }
        
        modulesTableView.reloadData()
        moduleCountLabel.stringValue = "\(mods.count) mapped modules detected in memory"
    }
    
    // MARK: - NSTableViewDataSource & Delegate
    
    public func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == modulesTableView {
            return displayedModules.count
        }
        return displayedProcesses.count
    }
    
    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView, tv == processTableView else { return }
        let row = tv.selectedRow
        guard row >= 0 && row < displayedProcesses.count else { return }
        inspectProcess(displayedProcesses[row])
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == modulesTableView {
            guard row >= 0 && row < displayedModules.count else { return nil }
            let mod = displayedModules[row]
            let identifier = tableColumn?.identifier.rawValue ?? ""
            
            let cell = NSTextField(labelWithString: "")
            cell.font = .systemFont(ofSize: 11)
            cell.lineBreakMode = .byTruncatingMiddle
            
            switch identifier {
            case "mod_name":
                cell.stringValue = mod.name
                cell.font = .systemFont(ofSize: 11, weight: .medium)
                cell.toolTip = mod.path
            case "mod_addr":
                cell.stringValue = mod.formattedBaseAddress
                cell.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                cell.textColor = .secondaryLabelColor
            case "mod_size":
                cell.stringValue = mod.formattedSize
                cell.font = .systemFont(ofSize: 11, weight: .regular)
                cell.textColor = .secondaryLabelColor
            default:
                break
            }
            return cell
        }
        
        // Process Table View
        guard row >= 0 && row < displayedProcesses.count else { return nil }
        let proc = displayedProcesses[row]
        let identifier = tableColumn?.identifier.rawValue ?? ""
        
        switch identifier {
        case "icon":
            let iv = NSImageView()
            if let app = NSRunningApplication(processIdentifier: proc.pid), let icon = app.icon {
                iv.image = icon
            } else {
                iv.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
                iv.contentTintColor = .secondaryLabelColor
            }
            return iv
            
        case "pid":
            let cell = NSTextField(labelWithString: "\(proc.pid)")
            cell.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.textColor = .secondaryLabelColor
            return cell
            
        case "name":
            let cell = NSTextField(labelWithString: proc.displayName)
            cell.font = .systemFont(ofSize: 12, weight: .medium)
            cell.lineBreakMode = .byTruncatingTail
            if let warn = proc.securityWarningText {
                cell.toolTip = warn
            }
            return cell
            
        case "arch":
            let pill = StatusPillView(
                text: proc.arch.rawValue.uppercased(),
                color: (proc.arch == .arm64) ? .systemPurple : ((proc.arch == .x86_64) ? .systemCyan : .systemGray)
            )
            return pill
            
        case "security":
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 3
            if proc.requiresLibraryValidation {
                let p = StatusPillView(text: "LV", color: .systemOrange, dotVisible: false)
                p.toolTip = "Library Validation Enforced"
                stack.addArrangedSubview(p)
            }
            if proc.isHardenedRuntime {
                let p = StatusPillView(text: "HR", color: .systemPurple, dotVisible: false)
                p.toolTip = "Hardened Runtime Active"
                stack.addArrangedSubview(p)
            }
            if proc.hasGetTaskAllow {
                let p = StatusPillView(text: "GTA", color: .systemGreen, dotVisible: false)
                p.toolTip = "get-task-allow (Debuggable)"
                stack.addArrangedSubview(p)
            }
            if stack.arrangedSubviews.isEmpty {
                let label = NSTextField(labelWithString: "Standard")
                label.font = .systemFont(ofSize: 10)
                label.textColor = .tertiaryLabelColor
                stack.addArrangedSubview(label)
            }
            return stack
            
        case "path":
            let cell = NSTextField(labelWithString: proc.displayPath)
            cell.font = .systemFont(ofSize: 11)
            cell.textColor = .secondaryLabelColor
            cell.lineBreakMode = .byTruncatingMiddle
            cell.toolTip = proc.path ?? "Protected System Process"
            return cell
            
        default:
            return nil
        }
    }
}
