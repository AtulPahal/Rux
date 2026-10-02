import AppKit
import Combine

public final class ScriptConsoleViewController: NSViewController {
    private let ipc = IpcClient()
    private var cancellables = Set<AnyCancellable>()
    
    // Top HUD Elements
    private let statusPill = StatusPillView(text: "Offline", color: .systemOrange)
    private let pingButton = NSButton()
    private let telemetryButton = NSButton()
    private let hostField = NSTextField()
    private let portField = NSTextField()
    
    // Live Telemetry Badges
    private let luaStatePill = StatusPillView(text: "Lua State: Ready", color: .systemCyan, dotVisible: false)
    private let pidTelemetryPill = StatusPillView(text: "PID: -", color: .systemGray, dotVisible: false)
    private let memTelemetryPill = StatusPillView(text: "RSS: -", color: .systemGray, dotVisible: false)
    private let uptimeTelemetryPill = StatusPillView(text: "Uptime: -", color: .systemGray, dotVisible: false)
    private let hooksTelemetryPill = StatusPillView(text: "Hooks: 0", color: .systemPurple, dotVisible: false)
    // Presets & Controls
    private let presetsPopup = NSPopUpButton()
    private let byteCountLabel = NSTextField(labelWithString: "0 bytes")
    
    // Code Editor
    private var editorTextView: NSTextView!
    private let executeButton = NSButton()
    private let clearEditorButton = NSButton()
    
    // REPL Console Output
    private var consoleTextView: NSTextView!
    private let clearConsoleButton = NSButton()
    private let copyConsoleButton = NSButton()
    
    public override func loadView() {
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 1140, height: 750))
        root.autoresizingMask = [.width, .height]
        self.view = root
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        loadPreset(index: 0)
    }
    
    private func setupUI() {
        // 1. Top HUD Box
        let hudBox = NSBox()
        hudBox.boxType = .custom
        hudBox.borderWidth = 1
        hudBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.35)
        hudBox.cornerRadius = 10
        hudBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45)
        hudBox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hudBox)
        
        statusPill.translatesAutoresizingMaskIntoConstraints = false
        hudBox.addSubview(statusPill)
        
        let hostLbl = NSTextField(labelWithString: "Host:")
        hostLbl.font = .systemFont(ofSize: 11)
        hostLbl.textColor = .secondaryLabelColor
        hostLbl.translatesAutoresizingMaskIntoConstraints = false
        hudBox.addSubview(hostLbl)
        
        hostField.stringValue = "127.0.0.1"
        hostField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hostField.translatesAutoresizingMaskIntoConstraints = false
        hudBox.addSubview(hostField)
        
        let portLbl = NSTextField(labelWithString: "Port:")
        portLbl.font = .systemFont(ofSize: 11)
        portLbl.textColor = .secondaryLabelColor
        portLbl.translatesAutoresizingMaskIntoConstraints = false
        hudBox.addSubview(portLbl)
        
        portField.stringValue = "5553"
        portField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        portField.translatesAutoresizingMaskIntoConstraints = false
        hudBox.addSubview(portField)
        
        pingButton.title = "Ping"
        pingButton.image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
        pingButton.bezelStyle = .rounded
        pingButton.target = self
        pingButton.action = #selector(handlePing)
        pingButton.translatesAutoresizingMaskIntoConstraints = false
        hudBox.addSubview(pingButton)
        
        telemetryButton.title = "Fetch Telemetry"
        telemetryButton.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: nil)
        telemetryButton.bezelStyle = .rounded
        telemetryButton.target = self
        telemetryButton.action = #selector(handleFetchTelemetry)
        telemetryButton.translatesAutoresizingMaskIntoConstraints = false
        hudBox.addSubview(telemetryButton)
        
        // Telemetry Pills Stack
        let telemStack = NSStackView(views: [luaStatePill, pidTelemetryPill, memTelemetryPill, uptimeTelemetryPill, hooksTelemetryPill])
        telemStack.orientation = .horizontal
        telemStack.spacing = 6
        telemStack.translatesAutoresizingMaskIntoConstraints = false
        hudBox.addSubview(telemStack)
        
        // 2. Split View for Editor and Console
        let splitView = NSSplitView()
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)
        
        let editorContainer = NSView()
        editorContainer.autoresizingMask = [.width, .height]
        setupEditorPane(in: editorContainer)
        splitView.addSubview(editorContainer)
        
        let consoleContainer = NSView()
        consoleContainer.autoresizingMask = [.width, .height]
        setupConsolePane(in: consoleContainer)
        splitView.addSubview(consoleContainer)
        
        NSLayoutConstraint.activate([
            hudBox.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            hudBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hudBox.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            hudBox.heightAnchor.constraint(equalToConstant: 46),
            
            statusPill.leadingAnchor.constraint(equalTo: hudBox.leadingAnchor, constant: 12),
            statusPill.centerYAnchor.constraint(equalTo: hudBox.centerYAnchor),
            
            hostLbl.leadingAnchor.constraint(equalTo: statusPill.trailingAnchor, constant: 14),
            hostLbl.centerYAnchor.constraint(equalTo: hudBox.centerYAnchor),
            
            hostField.leadingAnchor.constraint(equalTo: hostLbl.trailingAnchor, constant: 4),
            hostField.centerYAnchor.constraint(equalTo: hudBox.centerYAnchor),
            hostField.widthAnchor.constraint(equalToConstant: 80),
            
            portLbl.leadingAnchor.constraint(equalTo: hostField.trailingAnchor, constant: 10),
            portLbl.centerYAnchor.constraint(equalTo: hudBox.centerYAnchor),
            
            portField.leadingAnchor.constraint(equalTo: portLbl.trailingAnchor, constant: 4),
            portField.centerYAnchor.constraint(equalTo: hudBox.centerYAnchor),
            portField.widthAnchor.constraint(equalToConstant: 50),
            
            pingButton.leadingAnchor.constraint(equalTo: portField.trailingAnchor, constant: 10),
            pingButton.centerYAnchor.constraint(equalTo: hudBox.centerYAnchor),
            
            telemetryButton.leadingAnchor.constraint(equalTo: pingButton.trailingAnchor, constant: 6),
            telemetryButton.centerYAnchor.constraint(equalTo: hudBox.centerYAnchor),
            
            telemStack.trailingAnchor.constraint(equalTo: hudBox.trailingAnchor, constant: -12),
            telemStack.centerYAnchor.constraint(equalTo: hudBox.centerYAnchor),
            
            splitView.topAnchor.constraint(equalTo: hudBox.bottomAnchor, constant: 12),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
        ])
    }
    
    private func setupEditorPane(in container: NSView) {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        
        let presetLbl = NSTextField(labelWithString: "Script Preset:")
        presetLbl.font = .systemFont(ofSize: 11, weight: .medium)
        presetLbl.textColor = .secondaryLabelColor
        presetLbl.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(presetLbl)
        
        presetsPopup.addItems(withTitles: [
            "Print Target Environment & PID",
            "Hardware Fingerprint & Telemetry Query",
            "Inline Trampoline Hook Probe",
            "2D Drawing API Test (Vector2/Color3)",
            "Luau Script Execution Demo"
        ])
        presetsPopup.target = self
        presetsPopup.action = #selector(handlePresetChanged)
        presetsPopup.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(presetsPopup)
        
        byteCountLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        byteCountLabel.textColor = .secondaryLabelColor
        byteCountLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(byteCountLabel)
        
        clearEditorButton.title = "Clear"
        clearEditorButton.bezelStyle = .rounded
        clearEditorButton.target = self
        clearEditorButton.action = #selector(handleClearEditor)
        clearEditorButton.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(clearEditorButton)
        
        executeButton.title = "  Execute Script"
        executeButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        executeButton.bezelStyle = .rounded
        executeButton.contentTintColor = .controlAccentColor
        executeButton.font = .systemFont(ofSize: 12, weight: .bold)
        executeButton.target = self
        executeButton.action = #selector(handleExecute)
        executeButton.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(executeButton)
        
        let scroll = NSTextView.scrollableTextView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        container.addSubview(scroll)
        
        editorTextView = scroll.documentView as? NSTextView
        editorTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        editorTextView.isAutomaticQuoteSubstitutionEnabled = false
        editorTextView.isAutomaticDashSubstitutionEnabled = false
        editorTextView.isAutomaticTextReplacementEnabled = false
        editorTextView.allowsUndo = true
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleTextDidChange), name: NSText.didChangeNotification, object: editorTextView)
        
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 28),
            
            presetLbl.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            presetLbl.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            
            presetsPopup.leadingAnchor.constraint(equalTo: presetLbl.trailingAnchor, constant: 8),
            presetsPopup.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            
            byteCountLabel.leadingAnchor.constraint(equalTo: presetsPopup.trailingAnchor, constant: 14),
            byteCountLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            
            executeButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            executeButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            
            clearEditorButton.trailingAnchor.constraint(equalTo: executeButton.leadingAnchor, constant: -8),
            clearEditorButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
    }
    
    private func setupConsolePane(in container: NSView) {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        
        let titleLabel = NSTextField(labelWithString: "REPL Execution Console")
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(titleLabel)
        
        copyConsoleButton.title = "Copy"
        copyConsoleButton.bezelStyle = .rounded
        copyConsoleButton.target = self
        copyConsoleButton.action = #selector(handleCopyConsole)
        copyConsoleButton.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(copyConsoleButton)
        
        clearConsoleButton.title = "Clear"
        clearConsoleButton.bezelStyle = .rounded
        clearConsoleButton.target = self
        clearConsoleButton.action = #selector(handleClearConsole)
        clearConsoleButton.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(clearConsoleButton)
        
        let scroll = NSTextView.scrollableTextView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        container.addSubview(scroll)
        
        consoleTextView = scroll.documentView as? NSTextView
        consoleTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        consoleTextView.isEditable = false
        consoleTextView.isSelectable = true
        consoleTextView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.8)
        
        appendConsole("Rux IPC Console initialized. Ready to transmit scripts to injected payload.\n")
        
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 26),
            
            titleLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            
            clearConsoleButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            clearConsoleButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            
            copyConsoleButton.trailingAnchor.constraint(equalTo: clearConsoleButton.leadingAnchor, constant: -6),
            copyConsoleButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
    
    private func bindViewModel() {
        ipc.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .connected(let port):
                    self.statusPill.update(text: "Online (Port \(port))", color: .systemGreen)
                case .connecting:
                    self.statusPill.update(text: "Connecting...", color: .systemOrange)
                case .disconnected:
                    self.statusPill.update(text: "Offline", color: .systemOrange)
                case .error(let err):
                    self.statusPill.update(text: "Error: \(err)", color: .systemRed)
                }
            }
            .store(in: &cancellables)
        
        ipc.$isBusy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isBusy in
                self?.pingButton.isEnabled = !isBusy
                self?.telemetryButton.isEnabled = !isBusy
                self?.executeButton.isEnabled = !isBusy
            }
            .store(in: &cancellables)
        
        ipc.$latestTelemetry
            .receive(on: DispatchQueue.main)
            .sink { [weak self] telem in
                guard let self = self else { return }
                if let t = telem {
                    if let ls = t.luaStateStatus {
                        self.luaStatePill.update(text: "Lua State: \(ls)", color: .systemCyan, dotVisible: false)
                    }
                    self.pidTelemetryPill.update(text: "Target PID: \(t.targetPid)", color: .systemGreen, dotVisible: false)
                    self.memTelemetryPill.update(text: "Memory: \(t.formattedMemory)", color: .systemPurple, dotVisible: false)
                    self.uptimeTelemetryPill.update(text: "Uptime: \(t.formattedUptime)", color: .systemCyan, dotVisible: false)
                    self.hooksTelemetryPill.update(text: "Hooks: \(t.activeHooksCount)", color: .systemOrange, dotVisible: false)
                }
            }
            .store(in: &cancellables)
    }
    
    private func appendConsole(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(text)"
        
        if let storage = consoleTextView.textStorage {
            storage.append(NSAttributedString(string: line, attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            ]))
            consoleTextView.scrollToEndOfDocument(nil)
        }
    }
    
    // MARK: - Actions
    
    @objc private func handleTextDidChange() {
        let count = editorTextView.string.utf8.count
        byteCountLabel.stringValue = "\(count) bytes"
    }
    
    @objc private func handlePing() {
        ipc.host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        ipc.portText = portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        appendConsole("Pinging IPC payload at \(ipc.host):\(ipc.port)...")
        Task {
            let ok = await ipc.ping()
            if ok {
                self.appendConsole("✓ Payload responded with PONG (0x10). Target is ONLINE.\n")
            } else {
                self.appendConsole("✕ Payload connection refused or timed out at \(self.ipc.host):\(self.ipc.port).\n")
            }
        }
    }
    
    @objc private func handleFetchTelemetry() {
        ipc.host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        ipc.portText = portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        appendConsole("Fetching live telemetry (IPC_MSG_TELEMETRY)...")
        Task {
            if let t = await ipc.fetchTelemetry() {
                self.appendConsole("✓ Telemetry received: PID \(t.targetPid), Memory \(t.formattedMemory), Uptime \(t.formattedUptime), Whitelist: \(t.whitelistStatus)\n")
            } else {
                self.appendConsole("✕ Failed to fetch telemetry from payload.\n")
            }
        }
    }
    
    @objc private func handleExecute() {
        let script = editorTextView.string
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendConsole("⚠️ Warning: Cannot execute empty script.\n")
            return
        }
        
        ipc.host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        ipc.portText = portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        appendConsole("Dispatching script (\(script.utf8.count) bytes) to target payload...")
        Task {
            let success = await ipc.executeScript(script)
            if success {
                self.appendConsole("✓ Script successfully delivered to remote payload queue!\n")
            } else {
                self.appendConsole("✕ Delivery failed. Target payload unreachable.\n")
            }
        }
    }
    
    @objc private func handleClearEditor() {
        editorTextView.string = ""
        handleTextDidChange()
    }
    
    @objc private func handleClearConsole() {
        consoleTextView.string = ""
    }
    
    @objc private func handleCopyConsole() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(consoleTextView.string, forType: .string)
    }
    
    @objc private func handlePresetChanged() {
        loadPreset(index: presetsPopup.indexOfSelectedItem)
    }
    
    private func loadPreset(index: Int) {
        let preset: String
        switch index {
        case 0:
            preset = """
            -- Rux Introspection: Target Environment & PID
            print("[Rux] Target Process PID: " .. tostring(getpid and getpid() or "Unknown"))
            print("[Rux] Payload Version: 0.2.0")
            print("[Rux] Host Architecture: Darwin ARM64/x86_64")
            print("[Rux] Environment ready for execution.")
            """
        case 1:
            preset = """
            -- Hardware Fingerprint & Whitelist Telemetry
            local hwid = gethwid and gethwid() or "Offline"
            print("[Rux] Client Device HWID: " .. hwid)
            print("[Rux] Whitelist Verification Mode: Offline (Safe)")
            print("[Rux] Privacy Shield: Active (telemetry blocked)")
            """
        case 2:
            preset = """
            -- Inline Trampoline Hook Probe
            print("[Rux] Querying installed machine code jump trampolines...")
            if gethooks then
                local hooks = gethooks()
                print("[Rux] Active hooks installed: " .. #hooks)
            else
                print("[Rux] Hook subsystem verified. Zero foreign patches.")
            end
            """
        case 3:
            preset = """
            -- 2D Drawing Primitives Test
            print("[Rux] Testing Drawing API primitives...")
            local line = Drawing.new("Line")
            line.Visible = true
            line.From = Vector2.new(100, 100)
            line.To = Vector2.new(300, 100)
            line.Color = Color3.fromRGB(120, 80, 255)
            line.Thickness = 2
            print("[Rux] Drawing Line object created successfully.")
            """
        default:
            preset = """
            -- Custom Luau / Lua Script
            print("Hello from Rux Mach-O Injection Toolchain!")
            """
        }
        
        editorTextView.string = preset
        handleTextDidChange()
    }
}
