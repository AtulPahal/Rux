import AppKit

public enum SidebarTab: Int, CaseIterable {
    case files = 0
    case injector = 1
    case processes = 2
    case search = 3
    case settings = 4
}

public struct ScriptFileItem: Identifiable, Equatable {
    public let id: String
    public var name: String
    public var content: String
    public var isModified: Bool
    
    public init(id: String = UUID().uuidString, name: String, content: String, isModified: Bool = false) {
        self.id = id
        self.name = name
        self.content = content
        self.isModified = isModified
    }
}

public final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    // Callbacks
    public var onFileSelected: ((ScriptFileItem) -> Void)?
    public var onNewFileRequested: (() -> Void)?
    public var onInjectRequested: (() -> Void)?
    public var onProcessSelected: ((Int32, String, String) -> Void)?
    public var onToggleCollapse: (() -> Void)?
    
    // Services
    public let injectorService = InjectorService()
    public let processScanner = ProcessScanner()
    
    // Active State
    public private(set) var activeTab: SidebarTab = .files
    public private(set) var isPanelCollapsed: Bool = false
    
    // Script Files Model
    public var scriptFiles: [ScriptFileItem] = [
        ScriptFileItem(
            name: "Untitled-1.lua",
            content: "loadstring(game:HttpGet(\"https://raw.githubusercontent.com/Skibidiking123/Fisch1/refs/heads/main/FischMain\"))()",
            isModified: false
        ),
        ScriptFileItem(
            name: "Dex Explorer.lua",
            content: "-- Dark Dex Explorer V3\nloadstring(game:HttpGet(\"https://raw.githubusercontent.com/infyiff/backup/main/dex.lua\"))()",
            isModified: false
        ),
        ScriptFileItem(
            name: "Infinite Yield.lua",
            content: "-- Infinite Yield Admin Commands\nloadstring(game:HttpGet(\"https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source\"))()",
            isModified: false
        ),
        ScriptFileItem(
            name: "Remote Spy.lua",
            content: "-- SimpleSpy V3 (Remote Introspection)\nloadstring(game:HttpGet(\"https://raw.githubusercontent.com/ex70/SimpleSpy/main/source.lua\"))()",
            isModified: false
        )
    ]
    public private(set) var selectedFileIndex: Int = 0
    
    // UI - Main Container
    private let splitContainer = NSView()
    
    // Activity Bar (Icon Strip - Far Left)
    private let activityBar = NSView()
    private var activityButtons: [SidebarTab: NSButton] = [:]
    
    // Side Panel (Collapsible)
    private let panelContainer = NSView()
    private var panelWidthConstraint: NSLayoutConstraint!
    
    // File Viewer Subviews
    private let fileViewerHeader = NSView()
    private let fileTableView = NSTableView()
    private let fileScrollView = NSScrollView()
    
    // Injector Quick Panel Subviews
    private let injectorContainer = FlippedView()
    private let targetLabel = NSTextField(labelWithString: "Target: RobloxPlayer")
    private let targetStatusPill = StatusPillView(text: "Ready", color: .systemCyan)
    private let quickInjectButton = NSButton()
    private let adminCheck = NSButton(checkboxWithTitle: "Run with Administrator (sudo)", target: nil, action: nil)
    
    // Processes Panel Subviews
    private let processesContainer = FlippedView()
    private let processSearchField = NSSearchField()
    private let processTableView = NSTableView()
    private let processScrollView = NSScrollView()
    private var filteredProcesses: [ProcessItem] = []
    
    // Settings Subviews
    private let settingsContainer = FlippedView()
    
    public override func loadView() {
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: 260, height: 750))
        self.view = view
        setupUI()
        selectTab(.files)
        refreshProcessList()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    private func setupUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = IDETheme.sidebarBg.cgColor
        
        // 1. Activity Bar (Far Left Strip, 54px wide)
        activityBar.wantsLayer = true
        activityBar.layer?.backgroundColor = NSColor(red: 0.055, green: 0.063, blue: 0.086, alpha: 1.0).cgColor
        activityBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityBar)
        
        // Right border on activity bar
        let activityBorder = NSBox()
        activityBorder.boxType = .separator
        activityBorder.translatesAutoresizingMaskIntoConstraints = false
        activityBar.addSubview(activityBorder)
        
        // 2. Side Panel Container (206px wide)
        panelContainer.wantsLayer = true
        panelContainer.layer?.backgroundColor = IDETheme.sidebarBg.cgColor
        panelContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panelContainer)
        
        // Right border on panel
        let panelBorder = NSBox()
        panelBorder.boxType = .separator
        panelBorder.translatesAutoresizingMaskIntoConstraints = false
        panelContainer.addSubview(panelBorder)
        
        panelWidthConstraint = panelContainer.widthAnchor.constraint(equalToConstant: 206)
        
        NSLayoutConstraint.activate([
            // Activity Bar
            activityBar.topAnchor.constraint(equalTo: view.topAnchor),
            activityBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            activityBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            activityBar.widthAnchor.constraint(equalToConstant: 54),
            
            activityBorder.topAnchor.constraint(equalTo: activityBar.topAnchor),
            activityBorder.trailingAnchor.constraint(equalTo: activityBar.trailingAnchor),
            activityBorder.bottomAnchor.constraint(equalTo: activityBar.bottomAnchor),
            activityBorder.widthAnchor.constraint(equalToConstant: 1),
            
            // Panel Container
            panelContainer.topAnchor.constraint(equalTo: view.topAnchor),
            panelContainer.leadingAnchor.constraint(equalTo: activityBar.trailingAnchor),
            panelContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panelContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panelWidthConstraint,
            
            panelBorder.topAnchor.constraint(equalTo: panelContainer.topAnchor),
            panelBorder.trailingAnchor.constraint(equalTo: panelContainer.trailingAnchor),
            panelBorder.bottomAnchor.constraint(equalTo: panelContainer.bottomAnchor),
            panelBorder.widthAnchor.constraint(equalToConstant: 1)
        ])
        
        setupActivityBarButtons()
        setupFileViewerView()
        setupInjectorView()
        setupProcessesView()
        setupSettingsView()
    }
    
    // MARK: - Activity Bar Buttons
    
    private func setupActivityBarButtons() {
        let topStack = NSStackView()
        topStack.orientation = .vertical
        topStack.spacing = 14
        topStack.alignment = .centerX
        topStack.translatesAutoresizingMaskIntoConstraints = false
        activityBar.addSubview(topStack)
        
        // Top Icons: Files, Search, Injector, Processes
        let filesBtn = makeActivityButton(icon: "doc.on.doc", tag: SidebarTab.files.rawValue)
        let searchBtn = makeActivityButton(icon: "magnifyingglass", tag: SidebarTab.search.rawValue)
        let injectBtn = makeActivityButton(icon: "syringe", tag: SidebarTab.injector.rawValue)
        let procBtn = makeActivityButton(icon: "cpu", tag: SidebarTab.processes.rawValue)
        
        activityButtons[.files] = filesBtn
        activityButtons[.search] = searchBtn
        activityButtons[.injector] = injectBtn
        activityButtons[.processes] = procBtn
        
        topStack.addArrangedSubview(filesBtn)
        topStack.addArrangedSubview(searchBtn)
        topStack.addArrangedSubview(injectBtn)
        topStack.addArrangedSubview(procBtn)
        
        // Bottom Icons: Terminal prompt & Settings
        let bottomStack = NSStackView()
        bottomStack.orientation = .vertical
        bottomStack.spacing = 14
        bottomStack.alignment = .centerX
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        activityBar.addSubview(bottomStack)
        
        let termBtn = makeActivityButton(icon: "chevron.left.forwardslash.chevron.right", tag: 99)
        termBtn.target = self
        termBtn.action = #selector(handleTerminalToggle)
        
        let settingsBtn = makeActivityButton(icon: "gearshape", tag: SidebarTab.settings.rawValue)
        activityButtons[.settings] = settingsBtn
        
        bottomStack.addArrangedSubview(termBtn)
        bottomStack.addArrangedSubview(settingsBtn)
        
        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: activityBar.topAnchor, constant: 44),
            topStack.centerXAnchor.constraint(equalTo: activityBar.centerXAnchor),
            topStack.widthAnchor.constraint(equalToConstant: 44),
            
            bottomStack.bottomAnchor.constraint(equalTo: activityBar.bottomAnchor, constant: -16),
            bottomStack.centerXAnchor.constraint(equalTo: activityBar.centerXAnchor),
            bottomStack.widthAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    private func makeActivityButton(icon: String, tag: Int) -> NSButton {
        let btn = NSButton()
        btn.setButtonType(.momentaryChange)
        btn.isBordered = false
        btn.imagePosition = .imageOnly
        btn.tag = tag
        btn.target = self
        btn.action = #selector(handleActivityButton(_:))
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            btn.image = img
            btn.contentTintColor = IDETheme.textDim
        }
        
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 38),
            btn.heightAnchor.constraint(equalToConstant: 38)
        ])
        return btn
    }
    
    @objc private func handleActivityButton(_ sender: NSButton) {
        guard let tab = SidebarTab(rawValue: sender.tag) else { return }
        if activeTab == tab && !isPanelCollapsed {
            // Clicking same tab collapses panel (like VS Code)
            togglePanel()
        } else {
            if isPanelCollapsed {
                togglePanel()
            }
            selectTab(tab)
        }
    }
    
    @objc private func handleTerminalToggle() {
        onToggleCollapse?()
    }
    
    public func selectTab(_ tab: SidebarTab) {
        activeTab = tab
        
        // Update button visual states
        for (t, btn) in activityButtons {
            let isActive = (t == tab && !isPanelCollapsed)
            btn.contentTintColor = isActive ? IDETheme.accent : IDETheme.textDim
            btn.layer?.backgroundColor = isActive ? NSColor(red: 0.12, green: 0.15, blue: 0.22, alpha: 0.8).cgColor : NSColor.clear.cgColor
            btn.layer?.borderWidth = isActive ? 1 : 0
            btn.layer?.borderColor = isActive ? IDETheme.accent.withAlphaComponent(0.4).cgColor : NSColor.clear.cgColor
        }
        
        // Swap visible panel
        fileViewerHeader.isHidden = (tab != .files && tab != .search)
        fileScrollView.isHidden = (tab != .files && tab != .search)
        injectorContainer.isHidden = (tab != .injector)
        processesContainer.isHidden = (tab != .processes)
        settingsContainer.isHidden = (tab != .settings)
    }
    
    public func togglePanel() {
        isPanelCollapsed.toggle()
        panelWidthConstraint.constant = isPanelCollapsed ? 0 : 206
        panelContainer.isHidden = isPanelCollapsed
        
        // Re-apply button highlights
        selectTab(activeTab)
    }
    
    // MARK: - File Viewer View (Opiumware Style)
    
    private func setupFileViewerView() {
        // Header
        fileViewerHeader.translatesAutoresizingMaskIntoConstraints = false
        panelContainer.addSubview(fileViewerHeader)
        
        let titleLbl = NSTextField(labelWithString: "FILE VIEWER")
        titleLbl.font = .systemFont(ofSize: 11, weight: .bold)
        titleLbl.textColor = IDETheme.textDim
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        fileViewerHeader.addSubview(titleLbl)
        
        // Collapse arrow button `<`
        let collapseBtn = NSButton()
        collapseBtn.isBordered = false
        collapseBtn.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Collapse")
        collapseBtn.contentTintColor = IDETheme.textDim
        collapseBtn.target = self
        collapseBtn.action = #selector(handleCollapseClick)
        collapseBtn.translatesAutoresizingMaskIntoConstraints = false
        fileViewerHeader.addSubview(collapseBtn)
        
        // Options button `...`
        let moreBtn = NSButton()
        moreBtn.isBordered = false
        moreBtn.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Options")
        moreBtn.contentTintColor = IDETheme.textDim
        moreBtn.target = self
        moreBtn.action = #selector(handleMoreOptionsClick)
        moreBtn.translatesAutoresizingMaskIntoConstraints = false
        fileViewerHeader.addSubview(moreBtn)
        
        // Add File '+' Button
        let addFileBtn = NSButton()
        addFileBtn.isBordered = false
        addFileBtn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Script")
        addFileBtn.contentTintColor = IDETheme.textDim
        addFileBtn.target = self
        addFileBtn.action = #selector(handleNewFileClick)
        addFileBtn.translatesAutoresizingMaskIntoConstraints = false
        fileViewerHeader.addSubview(addFileBtn)
        
        NSLayoutConstraint.activate([
            fileViewerHeader.topAnchor.constraint(equalTo: panelContainer.topAnchor, constant: 40),
            fileViewerHeader.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor, constant: 14),
            fileViewerHeader.trailingAnchor.constraint(equalTo: panelContainer.trailingAnchor, constant: -10),
            fileViewerHeader.heightAnchor.constraint(equalToConstant: 24),
            
            titleLbl.leadingAnchor.constraint(equalTo: fileViewerHeader.leadingAnchor),
            titleLbl.centerYAnchor.constraint(equalTo: fileViewerHeader.centerYAnchor),
            
            moreBtn.trailingAnchor.constraint(equalTo: fileViewerHeader.trailingAnchor),
            moreBtn.centerYAnchor.constraint(equalTo: fileViewerHeader.centerYAnchor),
            moreBtn.widthAnchor.constraint(equalToConstant: 18),
            
            addFileBtn.trailingAnchor.constraint(equalTo: moreBtn.leadingAnchor, constant: -4),
            addFileBtn.centerYAnchor.constraint(equalTo: fileViewerHeader.centerYAnchor),
            addFileBtn.widthAnchor.constraint(equalToConstant: 18),
            
            collapseBtn.trailingAnchor.constraint(equalTo: addFileBtn.leadingAnchor, constant: -4),
            collapseBtn.centerYAnchor.constraint(equalTo: fileViewerHeader.centerYAnchor),
            collapseBtn.widthAnchor.constraint(equalToConstant: 18)
        ])
        
        // Table View
        fileScrollView.drawsBackground = false
        fileScrollView.hasVerticalScroller = true
        fileScrollView.translatesAutoresizingMaskIntoConstraints = false
        panelContainer.addSubview(fileScrollView)
        
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileCol"))
        col.width = 190
        fileTableView.addTableColumn(col)
        fileTableView.headerView = nil
        fileTableView.backgroundColor = .clear
        fileTableView.rowHeight = 28
        fileTableView.selectionHighlightStyle = .none
        fileTableView.dataSource = self
        fileTableView.delegate = self
        fileScrollView.documentView = fileTableView
        
        NSLayoutConstraint.activate([
            fileScrollView.topAnchor.constraint(equalTo: fileViewerHeader.bottomAnchor, constant: 10),
            fileScrollView.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor, constant: 6),
            fileScrollView.trailingAnchor.constraint(equalTo: panelContainer.trailingAnchor, constant: -6),
            fileScrollView.bottomAnchor.constraint(equalTo: panelContainer.bottomAnchor, constant: -12)
        ])
    }
    
    @objc private func handleCollapseClick() {
        togglePanel()
    }
    
    @objc private func handleNewFileClick() {
        let count = scriptFiles.count + 1
        let newFile = ScriptFileItem(
            name: "Untitled-\(count).lua",
            content: "-- Lua Script \(count)\nprint(\"Hello from Untitled-\(count)\")\n",
            isModified: false
        )
        scriptFiles.append(newFile)
        fileTableView.reloadData()
        selectFile(index: scriptFiles.count - 1)
        onNewFileRequested?()
    }
    
    @objc private func handleMoreOptionsClick() {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Lua Script", action: #selector(handleNewFileClick), keyEquivalent: "n")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Reload File Viewer", action: #selector(handleReloadFiles), keyEquivalent: "r")
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    @objc private func handleReloadFiles() {
        fileTableView.reloadData()
    }
    
    public func selectFile(index: Int) {
        guard index >= 0 && index < scriptFiles.count else { return }
        selectedFileIndex = index
        fileTableView.reloadData()
        onFileSelected?(scriptFiles[index])
    }
    
    // MARK: - NSTableViewDataSource & Delegate (Files)
    
    public func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == fileTableView {
            return scriptFiles.count
        } else if tableView == processTableView {
            return filteredProcesses.count
        }
        return 0
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == fileTableView {
            return makeFileRowView(row: row)
        } else if tableView == processTableView {
            return makeProcessRowView(row: row)
        }
        return nil
    }
    
    private func makeFileRowView(row: Int) -> NSView {
        let file = scriptFiles[row]
        let isSelected = (row == selectedFileIndex)
        
        let container = FlippedView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 5
        container.layer?.backgroundColor = isSelected ? NSColor(red: 0.118, green: 0.165, blue: 0.251, alpha: 0.7).cgColor : NSColor.clear.cgColor
        
        // Left active indicator strip (cyan vertical line)
        if isSelected {
            let indicator = NSView(frame: NSRect(x: 2, y: 5, width: 3, height: 18))
            indicator.wantsLayer = true
            indicator.layer?.backgroundColor = IDETheme.accent.cgColor
            indicator.layer?.cornerRadius = 1.5
            container.addSubview(indicator)
        }
        
        // File Icon
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        iconView.contentTintColor = isSelected ? IDETheme.accent : IDETheme.textDim
        iconView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconView)
        
        // File Title
        let nameLbl = NSTextField(labelWithString: file.name)
        nameLbl.font = .systemFont(ofSize: 12, weight: isSelected ? .medium : .regular)
        nameLbl.textColor = isSelected ? IDETheme.text : IDETheme.textDim
        nameLbl.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLbl)
        
        // Modified indicator dot if modified
        if file.isModified {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.backgroundColor = IDETheme.orange.cgColor
            dot.layer?.cornerRadius = 3
            dot.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(dot)
            
            NSLayoutConstraint.activate([
                dot.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                dot.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                dot.widthAnchor.constraint(equalToConstant: 6),
                dot.heightAnchor.constraint(equalToConstant: 6)
            ])
        }
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            
            nameLbl.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLbl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            nameLbl.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        
        return container
    }
    
    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView else { return }
        if tv == fileTableView {
            let row = tv.selectedRow
            if row >= 0 && row < scriptFiles.count {
                selectFile(index: row)
            }
        } else if tv == processTableView {
            let row = tv.selectedRow
            if row >= 0 && row < filteredProcesses.count {
                let proc = filteredProcesses[row]
                onProcessSelected?(proc.pid, proc.name, proc.arch.rawValue)
                targetLabel.stringValue = "Target: \(proc.name) (\(proc.pid))"
                targetStatusPill.update(text: proc.arch.rawValue, color: .systemPurple)
            }
        }
    }
    
    // MARK: - Injector Panel
    
    private func setupInjectorView() {
        injectorContainer.translatesAutoresizingMaskIntoConstraints = false
        injectorContainer.isHidden = true
        panelContainer.addSubview(injectorContainer)
        
        let titleLbl = NSTextField(labelWithString: "MACH-O INJECTOR")
        titleLbl.font = .systemFont(ofSize: 11, weight: .bold)
        titleLbl.textColor = IDETheme.textDim
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        injectorContainer.addSubview(titleLbl)
        
        targetLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        targetLabel.textColor = IDETheme.text
        targetLabel.translatesAutoresizingMaskIntoConstraints = false
        injectorContainer.addSubview(targetLabel)
        
        targetStatusPill.translatesAutoresizingMaskIntoConstraints = false
        injectorContainer.addSubview(targetStatusPill)
        
        adminCheck.font = .systemFont(ofSize: 11)
        adminCheck.state = .on
        adminCheck.translatesAutoresizingMaskIntoConstraints = false
        injectorContainer.addSubview(adminCheck)
        
        quickInjectButton.title = "Inject Payload"
        quickInjectButton.image = NSImage(systemSymbolName: "syringe", accessibilityDescription: nil)
        quickInjectButton.bezelStyle = .rounded
        quickInjectButton.target = self
        quickInjectButton.action = #selector(handleQuickInject)
        quickInjectButton.translatesAutoresizingMaskIntoConstraints = false
        injectorContainer.addSubview(quickInjectButton)
        
        NSLayoutConstraint.activate([
            injectorContainer.topAnchor.constraint(equalTo: panelContainer.topAnchor, constant: 40),
            injectorContainer.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor, constant: 12),
            injectorContainer.trailingAnchor.constraint(equalTo: panelContainer.trailingAnchor, constant: -12),
            injectorContainer.bottomAnchor.constraint(equalTo: panelContainer.bottomAnchor, constant: -12),
            
            titleLbl.topAnchor.constraint(equalTo: injectorContainer.topAnchor),
            titleLbl.leadingAnchor.constraint(equalTo: injectorContainer.leadingAnchor),
            
            targetLabel.topAnchor.constraint(equalTo: titleLbl.bottomAnchor, constant: 12),
            targetLabel.leadingAnchor.constraint(equalTo: injectorContainer.leadingAnchor),
            targetLabel.trailingAnchor.constraint(equalTo: injectorContainer.trailingAnchor),
            
            targetStatusPill.topAnchor.constraint(equalTo: targetLabel.bottomAnchor, constant: 8),
            targetStatusPill.leadingAnchor.constraint(equalTo: injectorContainer.leadingAnchor),
            
            adminCheck.topAnchor.constraint(equalTo: targetStatusPill.bottomAnchor, constant: 14),
            adminCheck.leadingAnchor.constraint(equalTo: injectorContainer.leadingAnchor),
            adminCheck.trailingAnchor.constraint(equalTo: injectorContainer.trailingAnchor),
            
            quickInjectButton.topAnchor.constraint(equalTo: adminCheck.bottomAnchor, constant: 14),
            quickInjectButton.leadingAnchor.constraint(equalTo: injectorContainer.leadingAnchor),
            quickInjectButton.trailingAnchor.constraint(equalTo: injectorContainer.trailingAnchor),
            quickInjectButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    @objc private func handleQuickInject() {
        onInjectRequested?()
    }
    
    // MARK: - Processes Panel
    
    private func setupProcessesView() {
        processesContainer.translatesAutoresizingMaskIntoConstraints = false
        processesContainer.isHidden = true
        panelContainer.addSubview(processesContainer)
        
        let titleLbl = NSTextField(labelWithString: "PROCESS EXPLORER")
        titleLbl.font = .systemFont(ofSize: 11, weight: .bold)
        titleLbl.textColor = IDETheme.textDim
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        processesContainer.addSubview(titleLbl)
        
        processSearchField.placeholderString = "Filter processes..."
        processSearchField.target = self
        processSearchField.action = #selector(handleProcessSearch)
        processSearchField.translatesAutoresizingMaskIntoConstraints = false
        processesContainer.addSubview(processSearchField)
        
        processScrollView.drawsBackground = false
        processScrollView.hasVerticalScroller = true
        processScrollView.translatesAutoresizingMaskIntoConstraints = false
        processesContainer.addSubview(processScrollView)
        
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ProcCol"))
        col.width = 180
        processTableView.addTableColumn(col)
        processTableView.headerView = nil
        processTableView.backgroundColor = .clear
        processTableView.rowHeight = 32
        processTableView.dataSource = self
        processTableView.delegate = self
        processScrollView.documentView = processTableView
        
        NSLayoutConstraint.activate([
            processesContainer.topAnchor.constraint(equalTo: panelContainer.topAnchor, constant: 40),
            processesContainer.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor, constant: 8),
            processesContainer.trailingAnchor.constraint(equalTo: panelContainer.trailingAnchor, constant: -8),
            processesContainer.bottomAnchor.constraint(equalTo: panelContainer.bottomAnchor, constant: -12),
            
            titleLbl.topAnchor.constraint(equalTo: processesContainer.topAnchor),
            titleLbl.leadingAnchor.constraint(equalTo: processesContainer.leadingAnchor, constant: 4),
            
            processSearchField.topAnchor.constraint(equalTo: titleLbl.bottomAnchor, constant: 8),
            processSearchField.leadingAnchor.constraint(equalTo: processesContainer.leadingAnchor),
            processSearchField.trailingAnchor.constraint(equalTo: processesContainer.trailingAnchor),
            
            processScrollView.topAnchor.constraint(equalTo: processSearchField.bottomAnchor, constant: 8),
            processScrollView.leadingAnchor.constraint(equalTo: processesContainer.leadingAnchor),
            processScrollView.trailingAnchor.constraint(equalTo: processesContainer.trailingAnchor),
            processScrollView.bottomAnchor.constraint(equalTo: processesContainer.bottomAnchor)
        ])
    }
    
    private func refreshProcessList() {
        Task {
            await processScanner.refreshAsync()
            await MainActor.run {
                self.filteredProcesses = self.processScanner.processes
                self.processTableView.reloadData()
            }
        }
    }
    
    @objc private func handleProcessSearch() {
        let q = processSearchField.stringValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            filteredProcesses = processScanner.processes
        } else {
            filteredProcesses = processScanner.processes.filter {
                $0.name.lowercased().contains(q) || "\($0.pid)".contains(q)
            }
        }
        processTableView.reloadData()
    }
    
    private func makeProcessRowView(row: Int) -> NSView {
        let proc = filteredProcesses[row]
        let container = FlippedView()
        
        let iconView = NSImageView()
        if let app = NSRunningApplication(processIdentifier: proc.pid), let icon = app.icon {
            iconView.image = icon
        } else {
            iconView.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconView)
        
        let nameLbl = NSTextField(labelWithString: proc.name)
        nameLbl.font = .systemFont(ofSize: 11, weight: .medium)
        nameLbl.textColor = IDETheme.text
        nameLbl.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLbl)
        
        let pidLbl = NSTextField(labelWithString: "\(proc.pid) • \(proc.arch.rawValue)")
        pidLbl.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pidLbl.textColor = IDETheme.textDim
        pidLbl.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pidLbl)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            
            nameLbl.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            nameLbl.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLbl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            
            pidLbl.topAnchor.constraint(equalTo: nameLbl.bottomAnchor, constant: 1),
            pidLbl.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            pidLbl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4)
        ])
        
        return container
    }
    
    // MARK: - Settings Panel
    
    private func setupSettingsView() {
        settingsContainer.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.isHidden = true
        panelContainer.addSubview(settingsContainer)
        
        let titleLbl = NSTextField(labelWithString: "SETTINGS")
        titleLbl.font = .systemFont(ofSize: 11, weight: .bold)
        titleLbl.textColor = IDETheme.textDim
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.addSubview(titleLbl)
        
        let hostLbl = NSTextField(labelWithString: "IPC Host: 127.0.0.1")
        hostLbl.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hostLbl.textColor = IDETheme.text
        hostLbl.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.addSubview(hostLbl)
        
        let portLbl = NSTextField(labelWithString: "IPC Port: 5553")
        portLbl.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        portLbl.textColor = IDETheme.text
        portLbl.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.addSubview(portLbl)
        
        let verLbl = NSTextField(labelWithString: "Rux Toolchain v0.2.0")
        verLbl.font = .systemFont(ofSize: 11)
        verLbl.textColor = IDETheme.textDim
        verLbl.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.addSubview(verLbl)
        
        NSLayoutConstraint.activate([
            settingsContainer.topAnchor.constraint(equalTo: panelContainer.topAnchor, constant: 40),
            settingsContainer.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor, constant: 12),
            settingsContainer.trailingAnchor.constraint(equalTo: panelContainer.trailingAnchor, constant: -12),
            settingsContainer.bottomAnchor.constraint(equalTo: panelContainer.bottomAnchor, constant: -12),
            
            titleLbl.topAnchor.constraint(equalTo: settingsContainer.topAnchor),
            titleLbl.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor),
            
            hostLbl.topAnchor.constraint(equalTo: titleLbl.bottomAnchor, constant: 12),
            hostLbl.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor),
            
            portLbl.topAnchor.constraint(equalTo: hostLbl.bottomAnchor, constant: 8),
            portLbl.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor),
            
            verLbl.topAnchor.constraint(equalTo: portLbl.bottomAnchor, constant: 16),
            verLbl.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor)
        ])
    }
}
