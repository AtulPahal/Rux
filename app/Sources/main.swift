import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        
        setupMainMenu()
        let windowController = MainWindowController()
        self.mainWindowController = windowController
        
        if let win = windowController.window {
            win.center()
            win.makeKeyAndOrderFront(nil)
        }
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // 1. App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        appMenu.addItem(withTitle: "About Rux", action: #selector(handleAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Rux", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Rux", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // 2. Edit Menu (Standard text editing shortcuts)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        // 3. View Menu (Navigation shortcuts)
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        
        let item1 = NSMenuItem(title: "Injector", action: #selector(handleSelectTab1), keyEquivalent: "1")
        let item2 = NSMenuItem(title: "Processes", action: #selector(handleSelectTab2), keyEquivalent: "2")
        let item3 = NSMenuItem(title: "Script Console", action: #selector(handleSelectTab3), keyEquivalent: "3")
        let item4 = NSMenuItem(title: "Diagnostics", action: #selector(handleSelectTab4), keyEquivalent: "4")
        let item5 = NSMenuItem(title: "Activity Logs", action: #selector(handleSelectTab5), keyEquivalent: "5")
        viewMenu.addItem(item1)
        viewMenu.addItem(item2)
        viewMenu.addItem(item3)
        viewMenu.addItem(item4)
        viewMenu.addItem(item5)
        // 3. Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        
        NSApp.mainMenu = mainMenu
    }
    
    @objc private func handleAbout() {
        NSApplication.shared.orderFrontStandardAboutPanel(
            options: [
                NSApplication.AboutPanelOptionKey.applicationName: "Rux",
                NSApplication.AboutPanelOptionKey.version: "0.2.0",
                NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                    string: "Rux — Production-grade Darwin Mach-O Dynamic Library Injection Toolchain for macOS.\nSupports Apple Silicon (ARM64) and Intel (x86_64)."
                )
            ]
        )
    }
    
    @objc private func handleSelectTab1() { mainWindowController?.selectTab(index: 0) }
    @objc private func handleSelectTab2() { mainWindowController?.selectTab(index: 1) }
    @objc private func handleSelectTab3() { mainWindowController?.selectTab(index: 2) }
    @objc private func handleSelectTab4() { mainWindowController?.selectTab(index: 3) }
    @objc private func handleSelectTab5() { mainWindowController?.selectTab(index: 4) }
}

// Application Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
