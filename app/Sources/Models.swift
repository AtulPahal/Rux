import Foundation

public enum LogLevel: String, CaseIterable, Identifiable {
    case info = "INFO"
    case success = "SUCCESS"
    case warning = "WARN"
    case error = "ERROR"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

public struct LogItem: Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    
    public init(level: LogLevel, message: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.message = message
    }
    
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

public enum CpuArch: String, CaseIterable, Identifiable {
    case arm64 = "arm64"
    case x86_64 = "x86_64"
    case unknown = "unknown"
    
    public var id: String { rawValue }
    
    public var badgeColorName: String {
        switch self {
        case .arm64: return "purple"
        case .x86_64: return "cyan"
        case .unknown: return "gray"
        }
    }
}

public struct ProcessItem: Identifiable, Hashable {
    public let id: Int32
    public var pid: Int32 { id }
    public let name: String
    public let path: String?
    public let arch: CpuArch
    
    public init(pid: Int32, name: String, path: String?, arch: CpuArch) {
        self.id = pid
        self.name = name
        self.path = path
        self.arch = arch
    }
    
    public var displayName: String {
        name.isEmpty ? "PID \(pid)" : name
    }
    
    public var displayPath: String {
        path ?? "System / Protected"
    }
}

public enum DlopenMode: String, CaseIterable, Identifiable {
    case now = "now"
    case lazy = "lazy"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .now: return "RTLD_NOW (Immediate)"
        case .lazy: return "RTLD_LAZY (Deferred)"
        }
    }
}

public struct InjectConfig {
    public var targetProcess: ProcessItem?
    public var targetPidText: String = ""
    public var targetNameText: String = "RobloxPlayer"
    public var targetDylibPath: String = ""
    public var dlopenMode: DlopenMode = .now
    public var timeoutMs: Double = 3000
    public var waitCompletion: Bool = true
    public var verbose: Bool = true
    public var useAdminPrivileges: Bool = true
    
    public init() {}
}

public struct DiagnosticItem: Identifiable, Equatable {
    public let id: Int
    public let title: String
    public let passed: Bool
    public let details: String
    
    public init(id: Int, title: String, passed: Bool, details: String) {
        self.id = id
        self.title = title
        self.passed = passed
        self.details = details
    }
}

public enum IpcStatus: Equatable {
    case disconnected
    case connecting
    case connected(port: Int)
    case error(String)
    
    public var isOnline: Bool {
        if case .connected = self { return true }
        return false
    }
}
