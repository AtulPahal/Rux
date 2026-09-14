import AppKit

public final class InjectorViewController: NSViewController {
    public var onSwitchToProcesses: (() -> Void)?
    
    private let injectorService = InjectorService()
    
    // UI Elements - Target Process
    private let processNameField = NSTextField()
    private let pidField = NSTextField()
    private let targetInfoLabel = NSTextField(labelWithString: "Configured target: RobloxPlayer")
    
    // UI Elements - Dylib
    private let dylibPathField = NSTextField()
    private let dylibStatusLabel = NSTextField(labelWithString: "")
    
    // UI Elements - Options
    private let modePopup = NSPopUpButton()
    private let timeoutSlider = NSSlider()
    private let timeoutLabel = NSTextField(labelWithString: "3000 ms")
    private let waitCompletionCheckbox = NSButton(checkboxWithTitle: "Wait for remote thread & dlopen() completion", target: nil, action: nil)
    private let verboseCheckbox = NSButton(checkboxWithTitle: "Enable verbose Mach diagnostic logs", target: nil, action: nil)
    private let adminCheckbox = NSButton(checkboxWithTitle: "Authenticate as Administrator (Touch ID / Password)", target: nil, action: nil)
    
    // UI Elements - Action
    private let injectButton = NSButton()
    private let progressIndicator = NSProgressIndicator()
    private let resultBox = NSBox()
    private let resultLabel = NSTextField(labelWithString: "")
    
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
    
    public func selectProcess(pid: Int32, name: String, arch: String) {
        pidField.stringValue = "\(pid)"
        processNameField.stringValue = name
        targetInfoLabel.stringValue = "✓ Target selected: \(name) (PID: \(pid), Arch: \(arch.uppercased()))"
        targetInfoLabel.textColor = .systemGreen
    }
    
    private func setupUI() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        
        NSLayoutConstraint.activate([
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
        
        // 1. Header Banner
        let headerView = createHeaderView()
        documentView.addSubview(headerView)
        
        // 2. Card 1: Target Process
        let processCard = createProcessCard()
        documentView.addSubview(processCard)
        
        // 3. Card 2: Dylib Payload
        let dylibCard = createDylibCard()
        documentView.addSubview(dylibCard)
        
        // 4. Card 3: Options & Privileges
        let optionsCard = createOptionsCard()
        documentView.addSubview(optionsCard)
        
        // 5. Action Section
        let actionView = createActionView()
        documentView.addSubview(actionView)
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 18),
            headerView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            headerView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            
            processCard.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 14),
            processCard.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            processCard.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            
            dylibCard.topAnchor.constraint(equalTo: processCard.bottomAnchor, constant: 14),
            dylibCard.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            dylibCard.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            
            optionsCard.topAnchor.constraint(equalTo: dylibCard.bottomAnchor, constant: 14),
            optionsCard.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            optionsCard.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            
            actionView.topAnchor.constraint(equalTo: optionsCard.bottomAnchor, constant: 16),
            actionView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            actionView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            actionView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -28)
        ])
        
        // Default initial values
        processNameField.stringValue = "RobloxPlayer"
        if let dylib = injectorService.resolveDefaultDylib() {
            dylibPathField.stringValue = dylib
            dylibStatusLabel.stringValue = "✓ Bundled payload verified: \(dylib)"
            dylibStatusLabel.textColor = .systemGreen
        }
    }
    
    // MARK: - Header
    private func createHeaderView() -> NSView {
        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let iconBg = NSView()
        iconBg.wantsLayer = true
        iconBg.layer?.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.25).cgColor
        iconBg.layer?.cornerRadius = 12
        iconBg.layer?.borderColor = NSColor.systemPurple.withAlphaComponent(0.6).cgColor
        iconBg.layer?.borderWidth = 1
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        
        let iconView = NSImageView(image: NSImage(systemSymbolName: "syringe.fill", accessibilityDescription: nil)!)
        iconView.contentTintColor = .systemPurple
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBg.addSubview(iconView)
        
        let titleLabel = NSTextField(labelWithString: "Darwin Mach-O Dynamic Library Injector")
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let subtitleLabel = NSTextField(labelWithString: "Position-independent Darwin code injection with ARM64 & x86_64 remote execution.")
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(iconBg)
        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            iconBg.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconBg.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 44),
            iconBg.heightAnchor.constraint(equalToConstant: 44),
            
            iconView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }
    
    // MARK: - Card 1: Process
    private func createProcessCard() -> CardView {
        let card = CardView(title: "1. Target Process Selection", icon: "cpu")
        
        let nameLbl = NSTextField(labelWithString: "Process Name:")
        nameLbl.font = .systemFont(ofSize: 12)
        nameLbl.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(nameLbl)
        
        processNameField.placeholderString = "e.g. RobloxPlayer"
        processNameField.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(processNameField)
        
        let pidLbl = NSTextField(labelWithString: "Or Target PID:")
        pidLbl.font = .systemFont(ofSize: 12)
        pidLbl.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(pidLbl)
        
        pidField.placeholderString = "e.g. 1234"
        pidField.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(pidField)
        
        let browseBtn = NSButton(title: "Browse Processes...", target: self, action: #selector(handleBrowseProcesses))
        browseBtn.bezelStyle = .rounded
        browseBtn.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(browseBtn)
        
        let presetLbl = NSTextField(labelWithString: "Quick Presets:")
        presetLbl.font = .systemFont(ofSize: 11)
        presetLbl.textColor = .secondaryLabelColor
        presetLbl.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(presetLbl)
        
        let robloxBtn = NSButton(title: "RobloxPlayer", target: self, action: #selector(setPresetRoblox))
        robloxBtn.bezelStyle = .inline
        robloxBtn.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(robloxBtn)
        
        let finderBtn = NSButton(title: "Finder", target: self, action: #selector(setPresetFinder))
        finderBtn.bezelStyle = .inline
        finderBtn.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(finderBtn)
        
        targetInfoLabel.font = .systemFont(ofSize: 11, weight: .medium)
        targetInfoLabel.textColor = .secondaryLabelColor
        targetInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(targetInfoLabel)
        
        NSLayoutConstraint.activate([
            nameLbl.topAnchor.constraint(equalTo: card.contentTopAnchor, constant: 12),
            nameLbl.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            
            processNameField.topAnchor.constraint(equalTo: nameLbl.bottomAnchor, constant: 4),
            processNameField.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            processNameField.widthAnchor.constraint(equalToConstant: 240),
            
            pidLbl.topAnchor.constraint(equalTo: nameLbl.topAnchor),
            pidLbl.leadingAnchor.constraint(equalTo: processNameField.trailingAnchor, constant: 16),
            
            pidField.topAnchor.constraint(equalTo: processNameField.topAnchor),
            pidField.leadingAnchor.constraint(equalTo: pidLbl.leadingAnchor),
            pidField.widthAnchor.constraint(equalToConstant: 110),
            
            browseBtn.centerYAnchor.constraint(equalTo: processNameField.centerYAnchor),
            browseBtn.leadingAnchor.constraint(equalTo: pidField.trailingAnchor, constant: 16),
            
            presetLbl.topAnchor.constraint(equalTo: processNameField.bottomAnchor, constant: 12),
            presetLbl.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            
            robloxBtn.centerYAnchor.constraint(equalTo: presetLbl.centerYAnchor),
            robloxBtn.leadingAnchor.constraint(equalTo: presetLbl.trailingAnchor, constant: 8),
            
            finderBtn.centerYAnchor.constraint(equalTo: presetLbl.centerYAnchor),
            finderBtn.leadingAnchor.constraint(equalTo: robloxBtn.trailingAnchor, constant: 8),
            
            targetInfoLabel.topAnchor.constraint(equalTo: presetLbl.bottomAnchor, constant: 10),
            targetInfoLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            targetInfoLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: targetInfoLabel.bottomAnchor, constant: 14)
        ])
        
        return card
    }
    
    // MARK: - Card 2: Dylib
    private func createDylibCard() -> CardView {
        let card = CardView(title: "2. Payload Dynamic Library (.dylib)", icon: "doc.badge.gearshape")
        
        dylibPathField.placeholderString = "Path to dynamic library (.dylib)"
        dylibPathField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        dylibPathField.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(dylibPathField)
        
        let browseBtn = NSButton(title: "Browse...", target: self, action: #selector(handleBrowseDylib))
        browseBtn.bezelStyle = .rounded
        browseBtn.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(browseBtn)
        
        let bundledBtn = NSButton(title: "Use Bundled Payload", target: self, action: #selector(handleUseBundledDylib))
        bundledBtn.bezelStyle = .rounded
        bundledBtn.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(bundledBtn)
        
        dylibStatusLabel.font = .systemFont(ofSize: 11)
        dylibStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(dylibStatusLabel)
        
        NSLayoutConstraint.activate([
            dylibPathField.topAnchor.constraint(equalTo: card.contentTopAnchor, constant: 12),
            dylibPathField.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            dylibPathField.trailingAnchor.constraint(equalTo: browseBtn.leadingAnchor, constant: -10),
            
            browseBtn.centerYAnchor.constraint(equalTo: dylibPathField.centerYAnchor),
            browseBtn.trailingAnchor.constraint(equalTo: bundledBtn.leadingAnchor, constant: -8),
            
            bundledBtn.centerYAnchor.constraint(equalTo: dylibPathField.centerYAnchor),
            bundledBtn.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            
            dylibStatusLabel.topAnchor.constraint(equalTo: dylibPathField.bottomAnchor, constant: 8),
            dylibStatusLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            dylibStatusLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: dylibStatusLabel.bottomAnchor, constant: 14)
        ])
        
        return card
    }
    
    // MARK: - Card 3: Options
    private func createOptionsCard() -> CardView {
        let card = CardView(title: "3. Injection Options & Privileges", icon: "slider.horizontal.3")
        
        let modeLbl = NSTextField(labelWithString: "dlopen Loading Mode:")
        modeLbl.font = .systemFont(ofSize: 12)
        modeLbl.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(modeLbl)
        
        modePopup.addItems(withTitles: ["RTLD_NOW (Immediate)", "RTLD_LAZY (Deferred)"])
        modePopup.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(modePopup)
        
        let timeoutTitleLbl = NSTextField(labelWithString: "Wait Timeout:")
        timeoutTitleLbl.font = .systemFont(ofSize: 12)
        timeoutTitleLbl.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(timeoutTitleLbl)
        
        timeoutSlider.minValue = 500
        timeoutSlider.maxValue = 10000
        timeoutSlider.doubleValue = 3000
        timeoutSlider.target = self
        timeoutSlider.action = #selector(handleTimeoutChanged)
        timeoutSlider.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(timeoutSlider)
        
        timeoutLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeoutLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(timeoutLabel)
        
        waitCompletionCheckbox.state = .on
        waitCompletionCheckbox.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(waitCompletionCheckbox)
        
        verboseCheckbox.state = .on
        verboseCheckbox.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(verboseCheckbox)
        
        adminCheckbox.state = .on
        adminCheckbox.font = .systemFont(ofSize: 13, weight: .medium)
        adminCheckbox.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(adminCheckbox)
        
        let adminHint = NSTextField(labelWithString: "Prompts for standard macOS admin authorization (required for task_for_pid on Darwin).")
        adminHint.font = .systemFont(ofSize: 10)
        adminHint.textColor = .secondaryLabelColor
        adminHint.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(adminHint)
        
        NSLayoutConstraint.activate([
            modeLbl.topAnchor.constraint(equalTo: card.contentTopAnchor, constant: 12),
            modeLbl.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            
            modePopup.centerYAnchor.constraint(equalTo: modeLbl.centerYAnchor),
            modePopup.leadingAnchor.constraint(equalTo: modeLbl.trailingAnchor, constant: 12),
            modePopup.widthAnchor.constraint(equalToConstant: 210),
            
            timeoutTitleLbl.topAnchor.constraint(equalTo: modeLbl.bottomAnchor, constant: 12),
            timeoutTitleLbl.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            
            timeoutSlider.centerYAnchor.constraint(equalTo: timeoutTitleLbl.centerYAnchor),
            timeoutSlider.leadingAnchor.constraint(equalTo: modePopup.leadingAnchor),
            timeoutSlider.widthAnchor.constraint(equalToConstant: 210),
            
            timeoutLabel.centerYAnchor.constraint(equalTo: timeoutSlider.centerYAnchor),
            timeoutLabel.leadingAnchor.constraint(equalTo: timeoutSlider.trailingAnchor, constant: 10),
            
            waitCompletionCheckbox.topAnchor.constraint(equalTo: timeoutTitleLbl.bottomAnchor, constant: 12),
            waitCompletionCheckbox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            
            verboseCheckbox.topAnchor.constraint(equalTo: waitCompletionCheckbox.bottomAnchor, constant: 8),
            verboseCheckbox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            
            adminCheckbox.topAnchor.constraint(equalTo: verboseCheckbox.bottomAnchor, constant: 10),
            adminCheckbox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            
            adminHint.topAnchor.constraint(equalTo: adminCheckbox.bottomAnchor, constant: 2),
            adminHint.leadingAnchor.constraint(equalTo: adminCheckbox.leadingAnchor, constant: 20),
            adminHint.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: adminHint.bottomAnchor, constant: 14)
        ])
        
        return card
    }
    
    // MARK: - Action Section
    private func createActionView() -> NSView {
        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        injectButton.title = "Inject Dynamic Library"
        injectButton.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        injectButton.imagePosition = .imageLeading
        injectButton.imageHugsTitle = true
        injectButton.bezelStyle = .regularSquare
        injectButton.isBordered = false
        injectButton.wantsLayer = true
        injectButton.layer?.backgroundColor = NSColor.systemPurple.cgColor
        injectButton.layer?.cornerRadius = 8
        injectButton.contentTintColor = .white
        injectButton.font = .systemFont(ofSize: 14, weight: .bold)
        injectButton.target = self
        injectButton.action = #selector(handleInject)
        injectButton.translatesAutoresizingMaskIntoConstraints = false
        
        progressIndicator.style = .spinning
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.controlSize = .small
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        resultBox.boxType = .custom
        resultBox.borderWidth = 1
        resultBox.cornerRadius = 8
        resultBox.isHidden = true
        resultBox.translatesAutoresizingMaskIntoConstraints = false
        
        resultLabel.font = .systemFont(ofSize: 12, weight: .medium)
        resultLabel.lineBreakMode = .byWordWrapping
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        resultBox.addSubview(resultLabel)
        
        NSLayoutConstraint.activate([
            resultLabel.topAnchor.constraint(equalTo: resultBox.topAnchor, constant: 10),
            resultLabel.leadingAnchor.constraint(equalTo: resultBox.leadingAnchor, constant: 12),
            resultLabel.trailingAnchor.constraint(equalTo: resultBox.trailingAnchor, constant: -12),
            resultLabel.bottomAnchor.constraint(equalTo: resultBox.bottomAnchor, constant: -10)
        ])
        
        container.addSubview(injectButton)
        container.addSubview(progressIndicator)
        container.addSubview(resultBox)
        
        NSLayoutConstraint.activate([
            injectButton.topAnchor.constraint(equalTo: container.topAnchor),
            injectButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            injectButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            injectButton.heightAnchor.constraint(equalToConstant: 44),
            
            progressIndicator.centerYAnchor.constraint(equalTo: injectButton.centerYAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: injectButton.trailingAnchor, constant: -16),
            
            resultBox.topAnchor.constraint(equalTo: injectButton.bottomAnchor, constant: 10),
            resultBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            resultBox.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: resultBox.bottomAnchor)
        ])
        
        return container
    }
    
    // MARK: - Actions
    
    @objc private func handleBrowseProcesses() {
        onSwitchToProcesses?()
    }
    
    @objc private func setPresetRoblox() {
        processNameField.stringValue = "RobloxPlayer"
        pidField.stringValue = ""
        targetInfoLabel.stringValue = "✓ Target configured: RobloxPlayer"
        targetInfoLabel.textColor = .systemPurple
    }
    
    @objc private func setPresetFinder() {
        processNameField.stringValue = "Finder"
        pidField.stringValue = ""
        targetInfoLabel.stringValue = "✓ Target configured: Finder"
        targetInfoLabel.textColor = .systemPurple
    }
    
    @objc private func handleBrowseDylib() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "dylib") ?? .data]
        panel.title = "Select Payload .dylib"
        
        if panel.runModal() == .OK, let url = panel.url {
            dylibPathField.stringValue = url.path
            validateDylibPath()
        }
    }
    
    @objc private func handleUseBundledDylib() {
        if let dylib = injectorService.resolveDefaultDylib() {
            dylibPathField.stringValue = dylib
            validateDylibPath()
        } else {
            dylibStatusLabel.stringValue = "✕ Bundled payload not found in standard directories."
            dylibStatusLabel.textColor = .systemRed
        }
    }
    
    private func validateDylibPath() {
        let path = dylibPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if FileManager.default.fileExists(atPath: path) {
            dylibStatusLabel.stringValue = "✓ File verified: \(path)"
            dylibStatusLabel.textColor = .systemGreen
        } else {
            dylibStatusLabel.stringValue = "✕ File does not exist at specified path."
            dylibStatusLabel.textColor = .systemOrange
        }
    }
    
    @objc private func handleTimeoutChanged() {
        timeoutLabel.stringValue = "\(Int(timeoutSlider.doubleValue)) ms"
    }
    
    @objc private func handleInject() {
        var config = InjectConfig()
        config.targetNameText = processNameField.stringValue
        config.targetPidText = pidField.stringValue
        config.targetDylibPath = dylibPathField.stringValue
        config.dlopenMode = (modePopup.indexOfSelectedItem == 0) ? .now : .lazy
        config.timeoutMs = timeoutSlider.doubleValue
        config.waitCompletion = (waitCompletionCheckbox.state == .on)
        config.verbose = (verboseCheckbox.state == .on)
        config.useAdminPrivileges = (adminCheckbox.state == .on)
        
        injectButton.isEnabled = false
        progressIndicator.startAnimation(nil)
        resultBox.isHidden = true
        
        Task {
            await injectorService.inject(config: config)
            
            await MainActor.run {
                self.injectButton.isEnabled = true
                self.progressIndicator.stopAnimation(nil)
                self.resultBox.isHidden = false
                
                let isSuccess = self.injectorService.lastSuccess ?? false
                let text = self.injectorService.lastResult ?? ""
                
                if isSuccess {
                    self.resultBox.borderColor = .systemGreen
                    self.resultBox.fillColor = NSColor.systemGreen.withAlphaComponent(0.12)
                    self.resultLabel.textColor = .systemGreen
                    self.resultLabel.stringValue = "✓ \(text)"
                } else {
                    self.resultBox.borderColor = .systemRed
                    self.resultBox.fillColor = NSColor.systemRed.withAlphaComponent(0.12)
                    self.resultLabel.textColor = .systemRed
                    self.resultLabel.stringValue = "✕ \(text)"
                }
            }
        }
    }
}
