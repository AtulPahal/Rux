import AppKit

public final class MainWindowController: NSWindowController {
    private let tabViewController = NSTabViewController()
    
    private let injectorVC = InjectorViewController()
    private let scannerVC = ProcessScannerViewController()
    private let scriptVC = ScriptConsoleViewController()
    private let diagnosticsVC = DiagnosticsViewController()
    private let logsVC = LogsViewController()
    
    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Rux — Mach-O Injection Toolchain"
        window.minSize = NSSize(width: 820, height: 700)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        
        setupTabs()
        wireNavigationCallbacks()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupTabs() {
        tabViewController.tabStyle = .toolbar
        
        let tab1 = NSTabViewItem(viewController: injectorVC)
        tab1.label = "Injector"
        tab1.image = NSImage(systemSymbolName: "syringe.fill", accessibilityDescription: "Injector")
        tabViewController.addTabViewItem(tab1)
        
        let tab2 = NSTabViewItem(viewController: scannerVC)
        tab2.label = "Processes"
        tab2.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Processes")
        tabViewController.addTabViewItem(tab2)
        
        let tab3 = NSTabViewItem(viewController: scriptVC)
        tab3.label = "Script Console"
        tab3.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Script Console")
        tabViewController.addTabViewItem(tab3)
        
        let tab4 = NSTabViewItem(viewController: diagnosticsVC)
        tab4.label = "Diagnostics"
        tab4.image = NSImage(systemSymbolName: "stethoscope", accessibilityDescription: "Diagnostics")
        tabViewController.addTabViewItem(tab4)
        
        let tab5 = NSTabViewItem(viewController: logsVC)
        tab5.label = "Activity Logs"
        tab5.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Logs")
        tabViewController.addTabViewItem(tab5)
        
        window?.contentViewController = tabViewController
    }
    
    private func wireNavigationCallbacks() {
        injectorVC.onSwitchToProcesses = { [weak self] in
            self?.tabViewController.selectedTabViewItemIndex = 1
        }
        
        scannerVC.onSelectProcess = { [weak self] pid, name, arch in
            self?.injectorVC.selectProcess(pid: pid, name: name, arch: arch)
            self?.tabViewController.selectedTabViewItemIndex = 0
        }
    }
}
