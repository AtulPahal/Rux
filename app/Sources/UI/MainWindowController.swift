import AppKit
import Combine

public final class MainWindowController: NSWindowController {
    // Services
    private let ipcClient = IpcClient()
    private let injectorService = InjectorService()
    private var cancellables = Set<AnyCancellable>()
    
    // UI Layout Components
    private let mainSplitView = NSSplitView()
    private let sidebarVC = SidebarViewController()
    
    // Editor & Workspace Container
    private let workspaceView = FlippedView()
    private let editorTabBar = EditorTabBarView()
    private let codeEditor = CodeEditorView()
    private let bottomPanel = BottomPanelView()
    private let statusBar = StatusBarView()
    // Constraints
    private var sidebarWidthConstraint: NSLayoutConstraint!
    private var bottomPanelHeightConstraint: NSLayoutConstraint!
    private var isBottomPanelCollapsed: Bool = false
    private let defaultBottomPanelHeight: CGFloat = 175
    // Tab Management
    private var openTabs: [EditorTabItem] = [
        EditorTabItem(
            title: "Untitled-1.lua",
            content: "loadstring(game:HttpGet(\"https://raw.githubusercontent.com/Skibidiking123/Fisch1/refs/heads/main/FischMain\"))()",
            isModified: false
        ),
        EditorTabItem(
            title: "Dex Explorer.lua",
            content: "-- Dark Dex Explorer V3\nloadstring(game:HttpGet(\"https://raw.githubusercontent.com/infyiff/backup/main/dex.lua\"))()",
            isModified: false
        ),
        EditorTabItem(
            title: "Infinite Yield.lua",
            content: "-- Infinite Yield Admin Commands\nloadstring(game:HttpGet(\"https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source\"))()",
            isModified: false
        ),
        EditorTabItem(
            title: "Remote Spy.lua",
            content: "-- SimpleSpy V3 (Remote Introspection)\nloadstring(game:HttpGet(\"https://raw.githubusercontent.com/ex70/SimpleSpy/main/source.lua\"))()",
            isModified: false
        )
    ]
    private var activeTabIndex: Int = 0
    
    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 900, height: 600)
        window.setFrameAutosaveName("RuxMainWindow")
        // Window Chrome & Opiumware Dark Appearance
        IDETheme.applyToWindow(window)
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        
        super.init(window: window)
        setupLayout()
        wireCallbacks()
        bindIpc()
        window.center()
        loadActiveTab()
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupLayout() {
        guard let window = window else { return }
        
        let rootContainer = FlippedView(frame: window.contentView?.bounds ?? .zero)
        rootContainer.autoresizingMask = [.width, .height]
        window.contentView = rootContainer
        
        // 1. Main Horizontal Split: [ Sidebar (Left) | Workspace (Right) ]
        mainSplitView.isVertical = true
        mainSplitView.dividerStyle = .thin
        mainSplitView.translatesAutoresizingMaskIntoConstraints = false
        rootContainer.addSubview(mainSplitView)
        
        // Add Sidebar View
        let sidebarView = sidebarVC.view
        sidebarView.autoresizingMask = [.width, .height]
        mainSplitView.addSubview(sidebarView)
        
        // Add Workspace View
        workspaceView.autoresizingMask = [.width, .height]
        mainSplitView.addSubview(workspaceView)
        
        NSLayoutConstraint.activate([
            mainSplitView.topAnchor.constraint(equalTo: rootContainer.topAnchor),
            mainSplitView.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            mainSplitView.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            mainSplitView.bottomAnchor.constraint(equalTo: rootContainer.bottomAnchor)
        ])
        
        mainSplitView.setPosition(260, ofDividerAt: 0)
        mainSplitView.adjustSubviews()
        // 2. Workspace View Hierarchy:
        // [ EditorTabBar (38px) ]
        // [ CodeEditorView (Flexible) ]
        // [ BottomPanelView (175px collapsible) ]
        // [ StatusBarView (22px) ]
        
        editorTabBar.translatesAutoresizingMaskIntoConstraints = false
        workspaceView.addSubview(editorTabBar)
        
        codeEditor.translatesAutoresizingMaskIntoConstraints = false
        workspaceView.addSubview(codeEditor)
        
        bottomPanel.translatesAutoresizingMaskIntoConstraints = false
        workspaceView.addSubview(bottomPanel)
        
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        workspaceView.addSubview(statusBar)
        
        bottomPanelHeightConstraint = bottomPanel.heightAnchor.constraint(equalToConstant: defaultBottomPanelHeight)
        
        NSLayoutConstraint.activate([
            // Top Tab Bar
            editorTabBar.topAnchor.constraint(equalTo: workspaceView.topAnchor, constant: 36), // Sits below macOS window titlebar
            editorTabBar.leadingAnchor.constraint(equalTo: workspaceView.leadingAnchor),
            editorTabBar.trailingAnchor.constraint(equalTo: workspaceView.trailingAnchor),
            editorTabBar.heightAnchor.constraint(equalToConstant: 38),
            // Middle Code Editor
            codeEditor.topAnchor.constraint(equalTo: editorTabBar.bottomAnchor),
            codeEditor.leadingAnchor.constraint(equalTo: workspaceView.leadingAnchor),
            codeEditor.trailingAnchor.constraint(equalTo: workspaceView.trailingAnchor),
            codeEditor.bottomAnchor.constraint(equalTo: bottomPanel.topAnchor),
            
            // Bottom Panel
            bottomPanel.leadingAnchor.constraint(equalTo: workspaceView.leadingAnchor),
            bottomPanel.trailingAnchor.constraint(equalTo: workspaceView.trailingAnchor),
            bottomPanel.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            bottomPanelHeightConstraint,
            
            // Status Bar
            statusBar.leadingAnchor.constraint(equalTo: workspaceView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: workspaceView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: workspaceView.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 22)
        ])
    }
    
    private func wireCallbacks() {
        // Tab Bar callbacks
        editorTabBar.onSelectTab = { [weak self] index in
            self?.selectTab(index: index)
        }
        
        editorTabBar.onCloseTab = { [weak self] index in
            self?.closeTab(index: index)
        }
        
        editorTabBar.onNewTab = { [weak self] in
            self?.createNewTab()
        }
        
        editorTabBar.onExecute = { [weak self] in
            self?.executeCurrentScript()
        }
        
        editorTabBar.onToggleWordWrap = { [weak self] in
            guard let self = self else { return }
            let isWrapped = self.codeEditor.toggleWordWrap()
            self.editorTabBar.isWordWrapActive = isWrapped
            self.statusBar.updateWordWrap(enabled: isWrapped)
            self.bottomPanel.appendOutput("[Editor] Word Wrap: \(isWrapped ? "ENABLED" : "DISABLED")\n", to: .terminal)
        }
        // Code Editor callbacks
        codeEditor.onTextChange = { [weak self] newText in
            guard let self = self, self.activeTabIndex >= 0 && self.activeTabIndex < self.openTabs.count else { return }
            self.openTabs[self.activeTabIndex].content = newText
            self.openTabs[self.activeTabIndex].isModified = true
            self.editorTabBar.updateActiveTabContent(newText, isModified: true)
        }
        
        codeEditor.onCursorChange = { [weak self] line, col in
            self?.statusBar.updateCursor(line: line, column: col)
        }
        
        // Bottom Panel collapse callback
        bottomPanel.onToggleCollapse = { [weak self] in
            self?.toggleBottomPanel()
        }
        
        sidebarVC.onToggleCollapse = { [weak self] in
            guard let self = self else { return }
            self.sidebarWidthConstraint.constant = self.sidebarVC.isPanelCollapsed ? 54 : 260
            self.toggleBottomPanel()
        }
        // Sidebar File Viewer Selection
        sidebarVC.onFileSelected = { [weak self] fileItem in
            guard let self = self else { return }
            // Check if file is already open in a tab
            if let existingIndex = self.openTabs.firstIndex(where: { $0.title == fileItem.name }) {
                self.selectTab(index: existingIndex)
            } else {
                let newTab = EditorTabItem(title: fileItem.name, content: fileItem.content, isModified: false)
                self.openTabs.append(newTab)
                self.selectTab(index: self.openTabs.count - 1)
            }
        }
        
        sidebarVC.onNewFileRequested = { [weak self] in
            self?.createNewTab()
        }
        
        sidebarVC.onInjectRequested = { [weak self] in
            self?.quickInjectPayload()
        }
        
        sidebarVC.onProcessSelected = { [weak self] pid, name, arch in
            self?.bottomPanel.appendOutput("[Process Explorer] Selected target: \(name) (PID: \(pid), Arch: \(arch))\n", to: .terminal)
        }
    }
    
    private func bindIpc() {
        ipcClient.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .connected:
                    self.statusBar.updateConnectionStatus(text: "Connected (127.0.0.1:5553)", isConnected: true)
                case .connecting:
                    self.statusBar.updateConnectionStatus(text: "Connecting...", isConnected: false)
                case .disconnected:
                    self.statusBar.updateConnectionStatus(text: "Offline", isConnected: false)
                case .error(let msg):
                    self.statusBar.updateConnectionStatus(text: "Error: \(msg)", isConnected: false)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Tab Management
    
    private func loadActiveTab() {
        guard activeTabIndex >= 0 && activeTabIndex < openTabs.count else { return }
        let tab = openTabs[activeTabIndex]
        codeEditor.text = tab.content
        editorTabBar.setTabs(openTabs, active: activeTabIndex)
        updateWindowTitle(for: tab.title)
    }
    public func selectTab(index: Int) {
        guard index >= 0 && index < openTabs.count else { return }
        activeTabIndex = index
        let tab = openTabs[index]
        codeEditor.text = tab.content
        editorTabBar.setTabs(openTabs, active: activeTabIndex)
        updateWindowTitle(for: tab.title)
    }
    
    private func closeTab(index: Int) {
        guard index >= 0 && index < openTabs.count else { return }
        openTabs.remove(at: index)
        if openTabs.isEmpty {
            openTabs.append(EditorTabItem(title: "Untitled-1.lua", content: "", isModified: false))
        }
        activeTabIndex = min(activeTabIndex, openTabs.count - 1)
        loadActiveTab()
    }
    
    private func createNewTab() {
        let count = openTabs.count + 1
        let item = EditorTabItem(title: "Untitled-\(count).lua", content: "-- New Script\nprint(\"Hello from Untitled-\(count)\")\n", isModified: false)
        openTabs.append(item)
        selectTab(index: openTabs.count - 1)
    }
    
    private func updateWindowTitle(for tabTitle: String) {
        window?.title = "\(tabTitle) — Rux"
    }
    // MARK: - Actions
    
    private func executeCurrentScript() {
        let script = codeEditor.text
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            bottomPanel.appendOutput("⚠️ Warning: Cannot execute empty script.\n", to: .terminal)
            return
        }
        
        let tabTitle = (activeTabIndex >= 0 && activeTabIndex < openTabs.count) ? openTabs[activeTabIndex].title : "Script"
        bottomPanel.appendOutput("▶ [Execute] Dispatching '\(tabTitle)' (\(script.utf8.count) bytes) to target payload...\n", to: .terminal)
        bottomPanel.appendOutput(">>> \(script)\n", to: .console)
        
        Task {
            let ok = await ipcClient.executeScript(script)
            await MainActor.run {
                if ok {
                    self.bottomPanel.appendOutput("✓ [Execute] Script delivered to payload queue successfully!\n", to: .terminal)
                } else {
                    self.bottomPanel.appendOutput("✕ [Execute] Delivery failed. Target payload unreachable at \(self.ipcClient.host):\(self.ipcClient.port).\n", to: .terminal)
                    self.bottomPanel.appendOutput("  Please inject payload into target process first via the Syringe / Attach button.\n", to: .terminal)
                }
            }
        }
    }
    
    private func quickInjectPayload() {
        bottomPanel.appendOutput("💉 [Injector] Starting dynamic library injection...\n", to: .terminal)
        
        var config = InjectConfig()
        config.targetNameText = "RobloxPlayer"
        config.useAdminPrivileges = true
        config.waitCompletion = true
        
        Task {
            await injectorService.inject(config: config)
            await MainActor.run {
                if self.injectorService.lastSuccess == true {
                    self.bottomPanel.appendOutput("✓ [Injector] Injection completed successfully! Remote module loaded.\n", to: .terminal)
                } else {
                    let err = self.injectorService.lastResult ?? "Unknown injection error"
                    self.bottomPanel.appendOutput("[-] [Injector] Injection failed:\n\(err)\n", to: .terminal)
                }
            }
        }
    }
    
    private func openScriptFileDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        
        if panel.runModal() == .OK, let url = panel.url {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let name = url.lastPathComponent
                let tab = EditorTabItem(title: name, content: content, isModified: false)
                openTabs.append(tab)
                selectTab(index: openTabs.count - 1)
                bottomPanel.appendOutput("✓ [File] Loaded script from: \(url.path)\n", to: .terminal)
            }
        }
    }
    
    private func toggleBottomPanel() {
        isBottomPanelCollapsed.toggle()
        bottomPanelHeightConstraint.constant = isBottomPanelCollapsed ? 32 : defaultBottomPanelHeight
        bottomPanel.textView.isHidden = isBottomPanelCollapsed
    }
}
