import Foundation
import AppKit
import Combine

@MainActor
public final class LogStore: ObservableObject {
    public static let shared = LogStore()
    
    @Published public private(set) var items: [LogItem] = []
    
    private let maxEntries = 1000
    
    public init() {
        log(.info, "Rux Engine initialized. Host Architecture: \(getSystemArch())")
    }
    
    public func log(_ level: LogLevel, _ message: String) {
        let item = LogItem(level: level, message: message)
        items.append(item)
        if items.count > maxEntries {
            items.removeFirst(items.count - maxEntries)
        }
    }
    
    public func clear() {
        items.removeAll()
        log(.info, "Log buffer cleared.")
    }
    
    public func exportText() -> String {
        items.map { "[\($0.formattedTime)] [\($0.level.rawValue)] \($0.message)" }
             .joined(separator: "\n")
    }
}

func getSystemArch() -> String {
    #if arch(arm64)
    return "ARM64 (Apple Silicon)"
    #elseif arch(x86_64)
    return "x86_64 (Intel)"
    #else
    return "Unknown"
    #endif
}
