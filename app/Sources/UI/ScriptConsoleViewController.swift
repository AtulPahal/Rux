import AppKit

public final class ScriptConsoleViewController: NSViewController {
    private let ipc = IpcClient()
    
    // Status Bar Elements
    private let statusDot = NSView()
    private let statusLabel = NSTextField(labelWithString: "Payload Offline (127.0.0.1:5553)")
    private let pingButton = NSButton()
    private let hostField = NSTextField()
    private let portField = NSTextField()
    
    // Presets & Controls
    private let presetsPopup = NSPopUpButton()
    private let byteCountLabel = NSTextField(labelWithString: "0 bytes")
    
    // Code Editor
    private var textView: NSTextView!
    private let executeButton = NSButton()
    private let executionStatusLabel = NSTextField(labelWithString: "")
    
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
        loadDefaultScript()
    }
    
    private func setupUI() {
        // 1. Top IPC Status Bar
        let statusBar = NSBox()
        statusBar.boxType = .custom
        statusBar.borderWidth = 1
        statusBar.borderColor = .separatorColor
        statusBar.cornerRadius = 8
        statusBar.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4)
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBar)
        
        statusDot.wantsLayer = true
        statusDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        statusDot.layer?.cornerRadius = 5
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        
        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = .systemOrange
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        pingButton.title = "Ping Payload"
        pingButton.image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
        pingButton.bezelStyle = .rounded
        pingButton.target = self
        pingButton.action = #selector(handlePing)
        pingButton.translatesAutoresizingMaskIntoConstraints = false
        
        let hostLbl = NSTextField(labelWithString: "Host:")
        hostLbl.font = .systemFont(ofSize: 11)
        hostLbl.textColor = .secondaryLabelColor
        hostLbl.translatesAutoresizingMaskIntoConstraints = false
        
        hostField.stringValue = "127.0.0.1"
        hostField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hostField.translatesAutoresizingMaskIntoConstraints = false
        
        let portLbl = NSTextField(labelWithString: "Port:")
        portLbl.font = .systemFont(ofSize: 11)
        portLbl.textColor = .secondaryLabelColor
        portLbl.translatesAutoresizingMaskIntoConstraints = false
        
        portField.stringValue = "5553"
        portField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        portField.translatesAutoresizingMaskIntoConstraints = false
        
        statusBar.addSubview(statusDot)
        statusBar.addSubview(statusLabel)
        statusBar.addSubview(pingButton)
        statusBar.addSubview(hostLbl)
        statusBar.addSubview(hostField)
        statusBar.addSubview(portLbl)
        statusBar.addSubview(portField)
        
        NSLayoutConstraint.activate([
            statusBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusBar.heightAnchor.constraint(equalToConstant: 44),
            
            statusDot.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 12),
            statusDot.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 10),
            statusDot.heightAnchor.constraint(equalToConstant: 10),
            
            statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            
            pingButton.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 12),
            pingButton.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            
            portField.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -12),
            portField.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            portField.widthAnchor.constraint(equalToConstant: 55),
            
            portLbl.trailingAnchor.constraint(equalTo: portField.leadingAnchor, constant: -4),
            portLbl.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            
            hostField.trailingAnchor.constraint(equalTo: portLbl.leadingAnchor, constant: -10),
            hostField.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            hostField.widthAnchor.constraint(equalToConstant: 90),
            
            hostLbl.trailingAnchor.constraint(equalTo: hostField.leadingAnchor, constant: -4),
            hostLbl.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor)
        ])
        
        // 2. Toolbar above editor (Presets, Clear, Copy)
        let editorToolbar = NSView()
        editorToolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editorToolbar)
        
        let presetTitle = NSTextField(labelWithString: "Preset Scripts:")
        presetTitle.font = .systemFont(ofSize: 12)
        presetTitle.textColor = .secondaryLabelColor
        presetTitle.translatesAutoresizingMaskIntoConstraints = false
        
        presetsPopup.addItems(withTitles: [
            "Hello World",
            "Query HWID & Fingerprint",
            "2D Drawing API Test",
            "HTTP Request Test"
        ])
        presetsPopup.target = self
        presetsPopup.action = #selector(handlePresetChanged)
        presetsPopup.translatesAutoresizingMaskIntoConstraints = false
        
        let clearBtn = NSButton(title: "Clear", target: self, action: #selector(handleClear))
        clearBtn.bezelStyle = .rounded
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        
        let copyBtn = NSButton(title: "Copy", target: self, action: #selector(handleCopy))
        copyBtn.bezelStyle = .rounded
        copyBtn.translatesAutoresizingMaskIntoConstraints = false
        
        editorToolbar.addSubview(presetTitle)
        editorToolbar.addSubview(presetsPopup)
        editorToolbar.addSubview(clearBtn)
        editorToolbar.addSubview(copyBtn)
        
        NSLayoutConstraint.activate([
            editorToolbar.topAnchor.constraint(equalTo: statusBar.bottomAnchor, constant: 10),
            editorToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            editorToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            editorToolbar.heightAnchor.constraint(equalToConstant: 28),
            
            presetTitle.leadingAnchor.constraint(equalTo: editorToolbar.leadingAnchor),
            presetTitle.centerYAnchor.constraint(equalTo: editorToolbar.centerYAnchor),
            
            presetsPopup.leadingAnchor.constraint(equalTo: presetTitle.trailingAnchor, constant: 8),
            presetsPopup.centerYAnchor.constraint(equalTo: editorToolbar.centerYAnchor),
            presetsPopup.widthAnchor.constraint(equalToConstant: 220),
            
            copyBtn.trailingAnchor.constraint(equalTo: editorToolbar.trailingAnchor),
            copyBtn.centerYAnchor.constraint(equalTo: editorToolbar.centerYAnchor),
            
            clearBtn.trailingAnchor.constraint(equalTo: copyBtn.leadingAnchor, constant: -8),
            clearBtn.centerYAnchor.constraint(equalTo: editorToolbar.centerYAnchor)
        ])
        
        // 3. Code Editor
        let scrollView = NSTextView.scrollableTextView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        view.addSubview(scrollView)
        
        textView = scrollView.documentView as? NSTextView
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.85)
        
        // 4. Bottom Action Bar
        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)
        
        byteCountLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        byteCountLabel.textColor = .secondaryLabelColor
        byteCountLabel.translatesAutoresizingMaskIntoConstraints = false
        
        executionStatusLabel.font = .systemFont(ofSize: 12)
        executionStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        executeButton.title = "  Execute Script via IPC"
        executeButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        executeButton.bezelStyle = .regularSquare
        executeButton.wantsLayer = true
        executeButton.layer?.backgroundColor = NSColor.systemPurple.cgColor
        executeButton.layer?.cornerRadius = 6
        executeButton.contentTintColor = .white
        executeButton.font = .systemFont(ofSize: 13, weight: .bold)
        executeButton.target = self
        executeButton.action = #selector(handleExecute)
        executeButton.translatesAutoresizingMaskIntoConstraints = false
        
        bottomBar.addSubview(byteCountLabel)
        bottomBar.addSubview(executionStatusLabel)
        bottomBar.addSubview(executeButton)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: editorToolbar.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -10),
            
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
            bottomBar.heightAnchor.constraint(equalToConstant: 36),
            
            byteCountLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            byteCountLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            
            executionStatusLabel.leadingAnchor.constraint(equalTo: byteCountLabel.trailingAnchor, constant: 16),
            executionStatusLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            
            executeButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            executeButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            executeButton.widthAnchor.constraint(equalToConstant: 200),
            executeButton.heightAnchor.constraint(equalToConstant: 34)
        ])
    }
    
    private func loadDefaultScript() {
        let script = """
-- Rux Injected Dynamic Library Script Console
-- Luau script environment with Drawing API, HTTP client, & Crypto engine

print("Hello from Rux macOS Client!")
print("Client Version: 0.2.0")

-- Example: Device Fingerprint & HWID query
if gethwid then
    print("HWID:", gethwid())
end
"""
        textView.string = script
        updateByteCount()
    }
    
    private func updateByteCount() {
        let bytes = textView.string.utf8.count
        byteCountLabel.stringValue = "\(bytes) bytes"
    }
    
    // MARK: - Actions
    
    @objc private func handlePing() {
        ipc.host = hostField.stringValue
        ipc.portText = portField.stringValue
        
        statusLabel.stringValue = "Pinging..."
        statusLabel.textColor = .secondaryLabelColor
        
        Task {
            let isOnline = await ipc.ping()
            await MainActor.run {
                if isOnline {
                    self.statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
                    self.statusLabel.stringValue = "Payload Connected (\(self.ipc.host):\(self.ipc.port))"
                    self.statusLabel.textColor = .systemGreen
                } else {
                    self.statusDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
                    self.statusLabel.stringValue = "Payload Offline (connection refused)"
                    self.statusLabel.textColor = .systemOrange
                }
            }
        }
    }
    
    @objc private func handlePresetChanged() {
        switch presetsPopup.indexOfSelectedItem {
        case 0:
            textView.string = """
print("Hello from Rux macOS Client!")
print("Client Version: 0.2.0")
"""
        case 1:
            textView.string = """
-- Query Hardware ID & Device Info
if gethwid then
    print("HWID:", gethwid())
end
"""
        case 2:
            textView.string = """
-- 2D Drawing API Primitive
if Drawing and Drawing.new then
    local line = Drawing.new("Line")
    line.Visible = true
    line.From = Vector2.new(150, 150)
    line.To = Vector2.new(450, 450)
    line.Color = Color3.fromRGB(0, 240, 255)
    line.Thickness = 3
    print("Drawing line successfully created on target screen!")
else
    print("Drawing API not available in current process")
end
"""
        case 3:
            textView.string = """
-- HTTP Request API
if request then
    local res = request({
        Url = "https://httpbin.org/get",
        Method = "GET"
    })
    print("HTTP GET Response Status:", res.StatusCode)
end
"""
        default:
            break
        }
        updateByteCount()
    }
    
    @objc private func handleClear() {
        textView.string = ""
        updateByteCount()
    }
    
    @objc private func handleCopy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
    }
    
    @objc private func handleExecute() {
        ipc.host = hostField.stringValue
        ipc.portText = portField.stringValue
        
        let script = textView.string
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            executionStatusLabel.stringValue = "Cannot execute empty script."
            executionStatusLabel.textColor = .systemOrange
            return
        }
        
        executeButton.isEnabled = false
        executionStatusLabel.stringValue = "Sending script to payload..."
        executionStatusLabel.textColor = .secondaryLabelColor
        
        Task {
            let success = await ipc.executeScript(script)
            await MainActor.run {
                self.executeButton.isEnabled = true
                if success {
                    self.statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
                    self.statusLabel.stringValue = "Payload Connected (\(self.ipc.host):\(self.ipc.port))"
                    self.statusLabel.textColor = .systemGreen
                    self.executionStatusLabel.stringValue = "✓ Script delivered and queued for execution!"
                    self.executionStatusLabel.textColor = .systemGreen
                } else {
                    self.executionStatusLabel.stringValue = "✕ Failed to deliver script. Target offline."
                    self.executionStatusLabel.textColor = .systemRed
                }
            }
        }
    }
}
