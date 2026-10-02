import AppKit

/// Opiumware-inspired dark navy IDE color palette.
public enum IDETheme {
    // Backgrounds
    static let bg = NSColor(red: 0.078, green: 0.090, blue: 0.120, alpha: 1.0)
    static let sidebarBg = NSColor(red: 0.067, green: 0.075, blue: 0.102, alpha: 1.0)
    static let editorBg = NSColor(red: 0.098, green: 0.110, blue: 0.145, alpha: 1.0)
    static let panelBg = NSColor(red: 0.082, green: 0.094, blue: 0.125, alpha: 1.0)
    static let tabBarBg = NSColor(red: 0.090, green: 0.102, blue: 0.133, alpha: 1.0)
    static let tabActive = NSColor(red: 0.118, green: 0.133, blue: 0.176, alpha: 1.0)
    
    // Borders & Dividers
    static let border = NSColor(red: 0.157, green: 0.176, blue: 0.220, alpha: 1.0)
    
    // Text
    static let text = NSColor(red: 0.847, green: 0.863, blue: 0.898, alpha: 1.0)
    static let textDim = NSColor(red: 0.447, green: 0.478, blue: 0.537, alpha: 1.0)
    
    // Accents
    static let accent = NSColor(red: 0.302, green: 0.545, blue: 1.0, alpha: 1.0)
    static let green = NSColor(red: 0.302, green: 0.843, blue: 0.529, alpha: 1.0)
    static let orange = NSColor(red: 1.0, green: 0.647, blue: 0.310, alpha: 1.0)
    static let red = NSColor(red: 1.0, green: 0.384, blue: 0.384, alpha: 1.0)
    
    // Syntax Highlighting
    static let string = NSColor(red: 0.596, green: 0.894, blue: 0.565, alpha: 1.0)
    static let keyword = NSColor(red: 0.769, green: 0.561, blue: 0.969, alpha: 1.0)
    static let number = NSColor(red: 0.980, green: 0.706, blue: 0.424, alpha: 1.0)
    static let comment = NSColor(red: 0.376, green: 0.412, blue: 0.478, alpha: 1.0)
    static let builtinFunc = NSColor(red: 0.459, green: 0.773, blue: 1.0, alpha: 1.0)
    
    // Shared font
    static let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let monoFontSmall = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let uiFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let uiFontBold = NSFont.systemFont(ofSize: 11, weight: .bold)
    
    /// Apply dark appearance to a window.
    static func applyToWindow(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = bg
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
    }
}
