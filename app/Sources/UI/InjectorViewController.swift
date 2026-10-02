import AppKit
import Combine

public final class InjectorViewController: NSViewController {
    public var onSwitchToProcesses: (() -> Void)?
    
    private let injectorService = InjectorService()
    private var cancellables = Set<AnyCancellable>()
    
    // Target Selection Mode
    private let targetModeSegmented = NSSegmentedControl(labels: ["Target by Name", "Target by PID"], trackingMode: .selectOne, target: nil, action: nil)
    private let processNameField = NSTextField()
    private let pidField = NSTextField()
    private let browseProcessesButton = NSButton()
    
    // Target Preview & Security Info
    private let targetPreviewBox = NSBox()
    private let targetIconView = NSImageView()
    private let targetTitleLabel = NSTextField(labelWithString: "Target: RobloxPlayer")
    private let targetSubtitleLabel = NSTextField(labelWithString: "Default target binary name")
    private let targetArchPill = StatusPillView(text: "ARM64", color: .systemPurple)
    private let targetSecPill = StatusPillView(text: "Standard", color: .systemGray, dotVisible: false)
    
    // Dylib Selection & Live Mach-O Inspector
    private let dylibPathField = NSTextField()
    private let browseDylibButton = NSButton()
    private let useBundledButton = NSButton()
    
    // Mach-O Inspector Card
    private let inspectorGroup = GroupSectionView(title: "Live Payload Mach-O Inspector", subtitle: "Architecture slices, dependencies & signature", iconName: "doc.badge.gearshape")
    private let dylibNameLabel = NSTextField(labelWithString: "No payload selected")
    private let dylibCompatBadge = StatusPillView(text: "Pending", color: .secondaryLabelColor)
    private let dylibArchSlicesLabel = NSTextField(labelWithString: "Slices: -")
    private let dylibInstallNameLabel = NSTextField(labelWithString: "Install Name: -")
    private let dylibDepsLabel = NSTextField(labelWithString: "Dependencies: -")
    private let dylibSignatureLabel = NSTextField(labelWithString: "Signature: -")
    private var currentInspection: DylibInspectionResult? = nil
    
    // Execution Options
    private let modePopup = NSPopUpButton()
    private let timeoutSlider = NSSlider()
    private let timeoutLabel = NSTextField(labelWithString: "3000 ms")
    private let waitCompletionCheckbox = NSButton(checkboxWithTitle: "Wait for remote thread & dlopen() completion", target: nil, action: nil)
    private let verboseCheckbox = NSButton(checkboxWithTitle: "Enable verbose Mach diagnostic logs", target: nil, action: nil)
    private let adminCheckbox = NSButton(checkboxWithTitle: "Authenticate with Administrator privileges (Touch ID / sudo)", target: nil, action: nil)
    
    // Pre-Flight Security Check Banner
    private let preflightBox = NSBox()
    private let preflightLabel = NSTextField(labelWithString: "Pre-Flight Status: Ready to inject.")
    
    // Action Section
    private let injectButton = NSButton()
    private let progressIndicator = NSProgressIndicator()
    private let resultBox = NSBox()
    private let resultLabel = NSTextField(labelWithString: "")
    
    // Target tracking
    private var currentTargetArch: CpuArch = .arm64
    private var currentTargetPid: Int32? = nil
    
    public override func loadView() {
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 1140, height: 750))
        root.autoresizingMask = [.width, .height]
        self.view = root
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        loadDefaultPayload()
    }
    
    public func selectProcess(pid: Int32, name: String, arch: String) {
        targetModeSegmented.selectedSegment = 1
        handleTargetModeChanged()
        
        pidField.stringValue = "\(pid)"
        processNameField.stringValue = name
        
        currentTargetPid = pid
        currentTargetArch = (arch.lowercased() == "arm64") ? .arm64 : ((arch.lowercased() == "x86_64") ? .x86_64 : .unknown)
        
        targetTitleLabel.stringValue = "\(name) (PID: \(pid))"
        targetSubtitleLabel.stringValue = "Target selected from Process Explorer"
        targetArchPill.update(text: arch.uppercased(), color: (currentTargetArch == .arm64) ? .systemPurple : .systemCyan)
        
        if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon {
            targetIconView.image = icon
        } else {
            targetIconView.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        }
        
        // Deep Fetch security for preflight
        Task.detached(priority: .userInitiated) {
            let sec = ProcessInspection.fetchSecurity(pid: pid)
            await MainActor.run {
                if let sec = sec {
                    if sec.requiresLibraryValidation && !sec.hasGetTaskAllow {
                        self.targetSecPill.update(text: "Library Validation", color: .systemOrange, dotVisible: false)
                        self.preflightLabel.stringValue = "⚠️ Pre-Flight Alert: Target enforces Library Validation (CS_REQUIRE_LV). Injection of third-party dylibs may be blocked by kernel."
                        self.preflightBox.borderColor = NSColor.systemOrange.withAlphaComponent(0.6)
                        self.preflightLabel.textColor = .systemOrange
                    } else if sec.isHardenedRuntime && !sec.hasGetTaskAllow {
                        self.targetSecPill.update(text: "Hardened Runtime", color: .systemRed, dotVisible: false)
                        self.preflightLabel.stringValue = "⛔ Target has Hardened Runtime without get-task-allow. Injection will fail unless SIP debugging restrictions are disabled (csrutil enable --without debug in Recovery OS)."
                        self.preflightBox.borderColor = NSColor.systemRed.withAlphaComponent(0.6)
                        self.preflightLabel.textColor = .systemRed
                    } else if sec.hasGetTaskAllow {
                        self.targetSecPill.update(text: "Debuggable", color: .systemGreen, dotVisible: false)
                        self.preflightLabel.stringValue = "✓ Target is debuggable (get-task-allow). Pre-flight checks passed."
                        self.preflightBox.borderColor = NSColor.systemGreen.withAlphaComponent(0.6)
                        self.preflightLabel.textColor = .systemGreen
                    } else {
                        self.targetSecPill.update(text: "Standard", color: .systemGray, dotVisible: false)
                        self.preflightLabel.stringValue = "✓ Target process ready for dynamic library injection."
                        self.preflightBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.3)
                        self.preflightLabel.textColor = .secondaryLabelColor
                    }
                }
                self.revalidateCompatibility()
            }
        }
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
        
        // 1. Header View
        let headerView = createHeaderView()
        documentView.addSubview(headerView)
        
        // 2. Target Process Card
        let processCard = createProcessCard()
        documentView.addSubview(processCard)
        
        // 3. Payload Dylib & Live Mach-O Inspector Card
        let dylibCard = createDylibCard()
        documentView.addSubview(dylibCard)
        
        // 4. Execution Options Card
        let optionsCard = createOptionsCard()
        documentView.addSubview(optionsCard)
        
        // 5. Action Section
        let actionView = createActionView()
        documentView.addSubview(actionView)
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 16),
            headerView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            headerView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            
            processCard.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 12),
            processCard.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            processCard.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            
            dylibCard.topAnchor.constraint(equalTo: processCard.bottomAnchor, constant: 12),
            dylibCard.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            dylibCard.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            
            optionsCard.topAnchor.constraint(equalTo: dylibCard.bottomAnchor, constant: 12),
            optionsCard.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            optionsCard.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            
            actionView.topAnchor.constraint(equalTo: optionsCard.bottomAnchor, constant: 16),
            actionView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            actionView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            actionView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24)
        ])
    }
    
    private func createHeaderView() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = NSTextField(labelWithString: "Mach-O Dynamic Library Injector")
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let subLabel = NSTextField(labelWithString: "Inject native dynamic libraries into remote Mach memory spaces with position-independent stubs and W^X memory enforcement.")
        subLabel.font = .systemFont(ofSize: 12)
        subLabel.textColor = .secondaryLabelColor
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(titleLabel)
        view.addSubview(subLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            
            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        return view
    }
    
    private func createProcessCard() -> NSView {
        let group = GroupSectionView(title: "1. Target Process Configuration", subtitle: "Select a running process by name or PID", iconName: "scope")
        
        targetModeSegmented.selectedSegment = 0
        targetModeSegmented.target = self
        targetModeSegmented.action = #selector(handleTargetModeChanged)
        targetModeSegmented.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(targetModeSegmented)
        
        processNameField.placeholderString = "Process Name (e.g. RobloxPlayer, Finder, Safari)"
        processNameField.stringValue = "RobloxPlayer"
        processNameField.font = .systemFont(ofSize: 12)
        processNameField.target = self
        processNameField.action = #selector(handleTargetTextChanged)
        processNameField.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(processNameField)
        
        pidField.placeholderString = "Target PID (e.g. 1234)"
        pidField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        pidField.target = self
        pidField.action = #selector(handleTargetTextChanged)
        pidField.isHidden = true
        pidField.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(pidField)
        
        browseProcessesButton.title = "Browse Processes..."
        browseProcessesButton.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        browseProcessesButton.bezelStyle = .rounded
        browseProcessesButton.target = self
        browseProcessesButton.action = #selector(handleBrowseProcesses)
        browseProcessesButton.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(browseProcessesButton)
        
        // Target Preview Box
        targetPreviewBox.boxType = .custom
        targetPreviewBox.borderWidth = 1
        targetPreviewBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.3)
        targetPreviewBox.cornerRadius = 8
        targetPreviewBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.3)
        targetPreviewBox.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(targetPreviewBox)
        
        targetIconView.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        targetIconView.contentTintColor = .controlAccentColor
        targetIconView.translatesAutoresizingMaskIntoConstraints = false
        targetPreviewBox.addSubview(targetIconView)
        
        targetTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        targetTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        targetPreviewBox.addSubview(targetTitleLabel)
        
        targetSubtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        targetSubtitleLabel.textColor = .secondaryLabelColor
        targetSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        targetPreviewBox.addSubview(targetSubtitleLabel)
        
        targetPreviewBox.addSubview(targetArchPill)
        targetPreviewBox.addSubview(targetSecPill)
        
        NSLayoutConstraint.activate([
            targetModeSegmented.topAnchor.constraint(equalTo: group.contentView.topAnchor),
            targetModeSegmented.leadingAnchor.constraint(equalTo: group.contentView.leadingAnchor),
            
            processNameField.topAnchor.constraint(equalTo: targetModeSegmented.bottomAnchor, constant: 10),
            processNameField.leadingAnchor.constraint(equalTo: group.contentView.leadingAnchor),
            processNameField.trailingAnchor.constraint(equalTo: browseProcessesButton.leadingAnchor, constant: -10),
            
            pidField.topAnchor.constraint(equalTo: targetModeSegmented.bottomAnchor, constant: 10),
            pidField.leadingAnchor.constraint(equalTo: group.contentView.leadingAnchor),
            pidField.trailingAnchor.constraint(equalTo: browseProcessesButton.leadingAnchor, constant: -10),
            
            browseProcessesButton.centerYAnchor.constraint(equalTo: processNameField.centerYAnchor),
            browseProcessesButton.trailingAnchor.constraint(equalTo: group.contentView.trailingAnchor),
            
            targetPreviewBox.topAnchor.constraint(equalTo: processNameField.bottomAnchor, constant: 10),
            targetPreviewBox.leadingAnchor.constraint(equalTo: group.contentView.leadingAnchor),
            targetPreviewBox.trailingAnchor.constraint(equalTo: group.contentView.trailingAnchor),
            targetPreviewBox.bottomAnchor.constraint(equalTo: group.contentView.bottomAnchor),
            targetPreviewBox.heightAnchor.constraint(equalToConstant: 44),
            
            targetIconView.leadingAnchor.constraint(equalTo: targetPreviewBox.leadingAnchor, constant: 12),
            targetIconView.centerYAnchor.constraint(equalTo: targetPreviewBox.centerYAnchor),
            targetIconView.widthAnchor.constraint(equalToConstant: 22),
            targetIconView.heightAnchor.constraint(equalToConstant: 22),
            
            targetTitleLabel.topAnchor.constraint(equalTo: targetPreviewBox.topAnchor, constant: 6),
            targetTitleLabel.leadingAnchor.constraint(equalTo: targetIconView.trailingAnchor, constant: 10),
            
            targetSubtitleLabel.topAnchor.constraint(equalTo: targetTitleLabel.bottomAnchor, constant: 1),
            targetSubtitleLabel.leadingAnchor.constraint(equalTo: targetTitleLabel.leadingAnchor),
            
            targetSecPill.trailingAnchor.constraint(equalTo: targetPreviewBox.trailingAnchor, constant: -12),
            targetSecPill.centerYAnchor.constraint(equalTo: targetPreviewBox.centerYAnchor),
            
            targetArchPill.trailingAnchor.constraint(equalTo: targetSecPill.leadingAnchor, constant: -6),
            targetArchPill.centerYAnchor.constraint(equalTo: targetPreviewBox.centerYAnchor)
        ])
        
        return group
    }
    
    private func createDylibCard() -> NSView {
        let group = GroupSectionView(title: "2. Dynamic Library Payload (.dylib)", subtitle: "Path to Mach-O payload with live binary inspector", iconName: "shippingbox")
        
        dylibPathField.placeholderString = "Path to dynamic library (.dylib)..."
        dylibPathField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        dylibPathField.target = self
        dylibPathField.action = #selector(handleDylibPathChanged)
        dylibPathField.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(dylibPathField)
        
        browseDylibButton.title = "Browse..."
        browseDylibButton.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        browseDylibButton.bezelStyle = .rounded
        browseDylibButton.target = self
        browseDylibButton.action = #selector(handleBrowseDylib)
        browseDylibButton.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(browseDylibButton)
        
        useBundledButton.title = "Use Bundled Payload"
        useBundledButton.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        useBundledButton.bezelStyle = .rounded
        useBundledButton.target = self
        useBundledButton.action = #selector(handleUseBundledPayload)
        useBundledButton.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(useBundledButton)
        
        // Embedded Live Mach-O Inspector Panel
        inspectorGroup.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(inspectorGroup)
        
        dylibNameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        dylibNameLabel.translatesAutoresizingMaskIntoConstraints = false
        inspectorGroup.contentView.addSubview(dylibNameLabel)
        
        dylibCompatBadge.translatesAutoresizingMaskIntoConstraints = false
        inspectorGroup.contentView.addSubview(dylibCompatBadge)
        
        dylibArchSlicesLabel.font = .systemFont(ofSize: 11, weight: .regular)
        dylibArchSlicesLabel.textColor = .secondaryLabelColor
        dylibArchSlicesLabel.translatesAutoresizingMaskIntoConstraints = false
        inspectorGroup.contentView.addSubview(dylibArchSlicesLabel)
        
        dylibInstallNameLabel.font = .systemFont(ofSize: 11, weight: .regular)
        dylibInstallNameLabel.textColor = .secondaryLabelColor
        dylibInstallNameLabel.lineBreakMode = .byTruncatingMiddle
        dylibInstallNameLabel.translatesAutoresizingMaskIntoConstraints = false
        inspectorGroup.contentView.addSubview(dylibInstallNameLabel)
        
        dylibDepsLabel.font = .systemFont(ofSize: 11, weight: .regular)
        dylibDepsLabel.textColor = .secondaryLabelColor
        dylibDepsLabel.translatesAutoresizingMaskIntoConstraints = false
        inspectorGroup.contentView.addSubview(dylibDepsLabel)
        
        dylibSignatureLabel.font = .systemFont(ofSize: 11, weight: .regular)
        dylibSignatureLabel.textColor = .secondaryLabelColor
        dylibSignatureLabel.translatesAutoresizingMaskIntoConstraints = false
        inspectorGroup.contentView.addSubview(dylibSignatureLabel)
        
        NSLayoutConstraint.activate([
            dylibPathField.topAnchor.constraint(equalTo: group.contentView.topAnchor),
            dylibPathField.leadingAnchor.constraint(equalTo: group.contentView.leadingAnchor),
            dylibPathField.trailingAnchor.constraint(equalTo: browseDylibButton.leadingAnchor, constant: -8),
            
            browseDylibButton.centerYAnchor.constraint(equalTo: dylibPathField.centerYAnchor),
            browseDylibButton.trailingAnchor.constraint(equalTo: useBundledButton.leadingAnchor, constant: -8),
            
            useBundledButton.centerYAnchor.constraint(equalTo: dylibPathField.centerYAnchor),
            useBundledButton.trailingAnchor.constraint(equalTo: group.contentView.trailingAnchor),
            
            inspectorGroup.topAnchor.constraint(equalTo: dylibPathField.bottomAnchor, constant: 10),
            inspectorGroup.leadingAnchor.constraint(equalTo: group.contentView.leadingAnchor),
            inspectorGroup.trailingAnchor.constraint(equalTo: group.contentView.trailingAnchor),
            inspectorGroup.bottomAnchor.constraint(equalTo: group.contentView.bottomAnchor),
            
            dylibNameLabel.topAnchor.constraint(equalTo: inspectorGroup.contentView.topAnchor),
            dylibNameLabel.leadingAnchor.constraint(equalTo: inspectorGroup.contentView.leadingAnchor),
            
            dylibCompatBadge.centerYAnchor.constraint(equalTo: dylibNameLabel.centerYAnchor),
            dylibCompatBadge.trailingAnchor.constraint(equalTo: inspectorGroup.contentView.trailingAnchor),
            
            dylibArchSlicesLabel.topAnchor.constraint(equalTo: dylibNameLabel.bottomAnchor, constant: 4),
            dylibArchSlicesLabel.leadingAnchor.constraint(equalTo: inspectorGroup.contentView.leadingAnchor),
            
            dylibInstallNameLabel.topAnchor.constraint(equalTo: dylibArchSlicesLabel.bottomAnchor, constant: 3),
            dylibInstallNameLabel.leadingAnchor.constraint(equalTo: inspectorGroup.contentView.leadingAnchor),
            dylibInstallNameLabel.trailingAnchor.constraint(equalTo: inspectorGroup.contentView.trailingAnchor),
            
            dylibDepsLabel.topAnchor.constraint(equalTo: dylibInstallNameLabel.bottomAnchor, constant: 3),
            dylibDepsLabel.leadingAnchor.constraint(equalTo: inspectorGroup.contentView.leadingAnchor),
            
            dylibSignatureLabel.topAnchor.constraint(equalTo: dylibDepsLabel.bottomAnchor, constant: 3),
            dylibSignatureLabel.leadingAnchor.constraint(equalTo: inspectorGroup.contentView.leadingAnchor),
            dylibSignatureLabel.bottomAnchor.constraint(equalTo: inspectorGroup.contentView.bottomAnchor)
        ])
        
        return group
    }
    
    private func createOptionsCard() -> NSView {
        let group = GroupSectionView(title: "3. Injection Options & Pre-Flight Check", subtitle: "Configure dlopen mode, timeouts, and elevation", iconName: "slider.horizontal.3")
        
        let modeLabel = NSTextField(labelWithString: "dlopen() Mode:")
        modeLabel.font = .systemFont(ofSize: 12)
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(modeLabel)
        
        modePopup.addItems(withTitles: ["RTLD_NOW (Immediate Symbol Binding)", "RTLD_LAZY (Deferred Binding)"])
        modePopup.selectItem(at: 0)
        modePopup.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(modePopup)
        
        let timeoutTitle = NSTextField(labelWithString: "Timeout:")
        timeoutTitle.font = .systemFont(ofSize: 12)
        timeoutTitle.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(timeoutTitle)
        
        timeoutSlider.minValue = 500
        timeoutSlider.maxValue = 10000
        timeoutSlider.doubleValue = 3000
        timeoutSlider.target = self
        timeoutSlider.action = #selector(handleTimeoutChanged)
        timeoutSlider.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(timeoutSlider)
        
        timeoutLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        timeoutLabel.textColor = .secondaryLabelColor
        timeoutLabel.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(timeoutLabel)
        
        waitCompletionCheckbox.state = .on
        waitCompletionCheckbox.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(waitCompletionCheckbox)
        
        verboseCheckbox.state = .on
        verboseCheckbox.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(verboseCheckbox)
        
        adminCheckbox.state = .on
        adminCheckbox.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(adminCheckbox)
        
        // Preflight Box
        preflightBox.boxType = .custom
        preflightBox.borderWidth = 1
        preflightBox.cornerRadius = 8
        preflightBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.3)
        preflightBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.3)
        preflightBox.translatesAutoresizingMaskIntoConstraints = false
        group.contentView.addSubview(preflightBox)
        
        preflightLabel.font = .systemFont(ofSize: 11, weight: .medium)
        preflightLabel.textColor = .secondaryLabelColor
        preflightLabel.lineBreakMode = .byWordWrapping
        preflightLabel.translatesAutoresizingMaskIntoConstraints = false
        preflightBox.addSubview(preflightLabel)
        
        NSLayoutConstraint.activate([
            modeLabel.topAnchor.constraint(equalTo: group.contentView.topAnchor),
            modeLabel.leadingAnchor.constraint(equalTo: group.contentView.leadingAnchor),
            
            modePopup.centerYAnchor.constraint(equalTo: modeLabel.centerYAnchor),
            modePopup.leadingAnchor.constraint(equalTo: modeLabel.trailingAnchor, constant: 10),
            
            timeoutTitle.centerYAnchor.constraint(equalTo: modeLabel.centerYAnchor),
            timeoutTitle.leadingAnchor.constraint(equalTo: modePopup.trailingAnchor, constant: 24),
            
            timeoutSlider.centerYAnchor.constraint(equalTo: modeLabel.centerYAnchor),
            timeoutSlider.leadingAnchor.constraint(equalTo: timeoutTitle.trailingAnchor, constant: 8),
            timeoutSlider.widthAnchor.constraint(equalToConstant: 120),
            
            timeoutLabel.centerYAnchor.constraint(equalTo: modeLabel.centerYAnchor),
            timeoutLabel.leadingAnchor.constraint(equalTo: timeoutSlider.trailingAnchor, constant: 8),
            
            waitCompletionCheckbox.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 12),
            waitCompletionCheckbox.leadingAnchor.constraint(equalTo: group.contentView.leadingAnchor),
            
            verboseCheckbox.topAnchor.constraint(equalTo: waitCompletionCheckbox.bottomAnchor, constant: 8),
            verboseCheckbox.leadingAnchor.constraint(equalTo: group.contentView.leadingAnchor),
            
            adminCheckbox.topAnchor.constraint(equalTo: verboseCheckbox.bottomAnchor, constant: 8),
            adminCheckbox.leadingAnchor.constraint(equalTo: group.contentView.leadingAnchor),
            
            preflightBox.topAnchor.constraint(equalTo: adminCheckbox.bottomAnchor, constant: 10),
            preflightBox.leadingAnchor.constraint(equalTo: group.contentView.leadingAnchor),
            preflightBox.trailingAnchor.constraint(equalTo: group.contentView.trailingAnchor),
            preflightBox.bottomAnchor.constraint(equalTo: group.contentView.bottomAnchor),
            
            preflightLabel.topAnchor.constraint(equalTo: preflightBox.topAnchor, constant: 8),
            preflightLabel.leadingAnchor.constraint(equalTo: preflightBox.leadingAnchor, constant: 10),
            preflightLabel.trailingAnchor.constraint(equalTo: preflightBox.trailingAnchor, constant: -10),
            preflightLabel.bottomAnchor.constraint(equalTo: preflightBox.bottomAnchor, constant: -8)
        ])
        
        return group
    }
    
    private func createActionView() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        injectButton.title = "  Inject Dynamic Library"
        injectButton.image = NSImage(systemSymbolName: "syringe.fill", accessibilityDescription: nil)
        injectButton.bezelStyle = .rounded
        injectButton.contentTintColor = .controlAccentColor
        injectButton.font = .systemFont(ofSize: 13, weight: .bold)
        injectButton.target = self
        injectButton.action = #selector(handleInject)
        injectButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(injectButton)
        
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressIndicator)
        
        resultBox.boxType = .custom
        resultBox.borderWidth = 1
        resultBox.cornerRadius = 8
        resultBox.isHidden = true
        resultBox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resultBox)
        
        resultLabel.font = .systemFont(ofSize: 12, weight: .medium)
        resultLabel.lineBreakMode = .byWordWrapping
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        resultBox.addSubview(resultLabel)
        
        NSLayoutConstraint.activate([
            injectButton.topAnchor.constraint(equalTo: view.topAnchor),
            injectButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            injectButton.heightAnchor.constraint(equalToConstant: 34),
            injectButton.widthAnchor.constraint(equalToConstant: 240),
            
            progressIndicator.centerYAnchor.constraint(equalTo: injectButton.centerYAnchor),
            progressIndicator.leadingAnchor.constraint(equalTo: injectButton.trailingAnchor, constant: 12),
            
            resultBox.topAnchor.constraint(equalTo: injectButton.bottomAnchor, constant: 12),
            resultBox.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultBox.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultBox.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            resultLabel.topAnchor.constraint(equalTo: resultBox.topAnchor, constant: 10),
            resultLabel.leadingAnchor.constraint(equalTo: resultBox.leadingAnchor, constant: 14),
            resultLabel.trailingAnchor.constraint(equalTo: resultBox.trailingAnchor, constant: -14),
            resultLabel.bottomAnchor.constraint(equalTo: resultBox.bottomAnchor, constant: -10)
        ])
        
        return view
    }
    
    private func bindViewModel() {
        injectorService.$isInjecting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isInjecting in
                self?.injectButton.isEnabled = !isInjecting
                if isInjecting {
                    self?.progressIndicator.startAnimation(nil)
                } else {
                    self?.progressIndicator.stopAnimation(nil)
                }
            }
            .store(in: &cancellables)
        
        injectorService.$lastResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] res in
                guard let self = self else { return }
                if let msg = res {
                    self.resultBox.isHidden = false
                    self.resultLabel.stringValue = msg
                    let isSuccess = self.injectorService.lastSuccess ?? false
                    if isSuccess {
                        self.resultBox.fillColor = NSColor.systemGreen.withAlphaComponent(0.12)
                        self.resultBox.borderColor = NSColor.systemGreen.withAlphaComponent(0.4)
                        self.resultLabel.textColor = .systemGreen
                    } else {
                        self.resultBox.fillColor = NSColor.systemRed.withAlphaComponent(0.12)
                        self.resultBox.borderColor = NSColor.systemRed.withAlphaComponent(0.4)
                        self.resultLabel.textColor = .systemRed
                    }
                } else {
                    self.resultBox.isHidden = true
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadDefaultPayload() {
        if let defaultDylib = injectorService.resolveDefaultDylib() {
            dylibPathField.stringValue = defaultDylib
            inspectDylib(atPath: defaultDylib)
        }
    }
    
    private func inspectDylib(atPath path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        
        guard let info = MachOInspector.inspect(url: url) else {
            dylibNameLabel.stringValue = url.lastPathComponent
            dylibCompatBadge.update(text: "Invalid Mach-O", color: .systemRed)
            dylibArchSlicesLabel.stringValue = "Slices: Unknown or damaged binary"
            dylibInstallNameLabel.stringValue = "Install Name: -"
            dylibDepsLabel.stringValue = "Dependencies: -"
            dylibSignatureLabel.stringValue = "Signature: -"
            currentInspection = nil
            return
        }
        
        currentInspection = info
        dylibNameLabel.stringValue = "\(info.fileName) (\(info.formattedSize))"
        
        let sliceStrings = info.slices.map { $0.arch.rawValue.uppercased() }.joined(separator: ", ")
        dylibArchSlicesLabel.stringValue = "Mach-O Slices: [\(sliceStrings)]"
        dylibInstallNameLabel.stringValue = "Install Name: \(info.installName) (v\(info.currentVersion))"
        dylibDepsLabel.stringValue = "Dependencies (\(info.dependencies.count)): \(info.dependencies.prefix(2).joined(separator: ", "))\(info.dependencies.count > 2 ? "..." : "")"
        
        let sigText: String
        if info.isSigned {
            if let team = info.teamIdentifier {
                sigText = "Signed (Team ID: \(team))"
            } else if info.isAdHoc {
                sigText = "Ad-Hoc Signed"
            } else {
                sigText = "Cryptographically Signed"
            }
        } else {
            sigText = "Unsigned"
        }
        dylibSignatureLabel.stringValue = "Code Signature: \(sigText)"
        
        revalidateCompatibility()
    }
    
    private func revalidateCompatibility() {
        guard let info = currentInspection else {
            dylibCompatBadge.update(text: "No Payload", color: .secondaryLabelColor)
            return
        }
        
        let isCompat = info.isCompatible(with: currentTargetArch)
        if isCompat {
            dylibCompatBadge.update(text: "✓ Compatible (\(currentTargetArch.rawValue.uppercased()))", color: .systemGreen)
        } else {
            dylibCompatBadge.update(text: "✕ Arch Mismatch", color: .systemRed)
        }
    }
    
    // MARK: - Actions
    
    @objc private func handleTargetModeChanged() {
        let isPid = (targetModeSegmented.selectedSegment == 1)
        processNameField.isHidden = isPid
        pidField.isHidden = !isPid
    }
    
    @objc private func handleTargetTextChanged() {
        if targetModeSegmented.selectedSegment == 0 {
            let name = processNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            targetTitleLabel.stringValue = "Target: \(name)"
            targetSubtitleLabel.stringValue = "Target by process name"
        } else {
            let pidStr = pidField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            targetTitleLabel.stringValue = "Target PID: \(pidStr)"
            targetSubtitleLabel.stringValue = "Target by PID"
        }
    }
    
    @objc private func handleBrowseProcesses() {
        onSwitchToProcesses?()
    }
    
    @objc private func handleBrowseDylib() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        
        if panel.runModal() == .OK, let url = panel.url {
            dylibPathField.stringValue = url.path
            inspectDylib(atPath: url.path)
        }
    }
    
    @objc private func handleUseBundledPayload() {
        if let defaultDylib = injectorService.resolveDefaultDylib() {
            dylibPathField.stringValue = defaultDylib
            inspectDylib(atPath: defaultDylib)
        }
    }
    
    @objc private func handleDylibPathChanged() {
        let path = dylibPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty {
            inspectDylib(atPath: path)
        }
    }
    
    @objc private func handleTimeoutChanged() {
        let ms = Int(timeoutSlider.doubleValue)
        timeoutLabel.stringValue = "\(ms) ms"
    }
    
    @objc private func handleInject() {
        var config = InjectConfig()
        
        let isPidMode = (targetModeSegmented.selectedSegment == 1)
        if isPidMode {
            config.targetPidText = pidField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            config.targetNameText = ""
        } else {
            config.targetNameText = processNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            config.targetPidText = ""
        }
        
        config.targetDylibPath = dylibPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.dlopenMode = (modePopup.indexOfSelectedItem == 0) ? .now : .lazy
        config.timeoutMs = timeoutSlider.doubleValue
        config.waitCompletion = (waitCompletionCheckbox.state == .on)
        config.verbose = (verboseCheckbox.state == .on)
        config.useAdminPrivileges = (adminCheckbox.state == .on)
        
        Task {
            await injectorService.inject(config: config)
        }
    }
}
