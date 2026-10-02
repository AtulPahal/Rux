import Foundation
import AppKit
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
    public let bundleIdentifier: String?
    public let isHardenedRuntime: Bool
    public let requiresLibraryValidation: Bool
    public let hasGetTaskAllow: Bool
    
    public init(
        pid: Int32,
        name: String,
        path: String?,
        arch: CpuArch,
        bundleIdentifier: String? = nil,
        isHardenedRuntime: Bool = false,
        requiresLibraryValidation: Bool = false,
        hasGetTaskAllow: Bool = false
    ) {
        self.id = pid
        self.name = name
        self.path = path
        self.arch = arch
        self.bundleIdentifier = bundleIdentifier
        self.isHardenedRuntime = isHardenedRuntime
        self.requiresLibraryValidation = requiresLibraryValidation
        self.hasGetTaskAllow = hasGetTaskAllow
    }
    
    public var displayName: String {
        name.isEmpty ? "PID \(pid)" : name
    }
    
    public var displayPath: String {
        path ?? "System / Protected"
    }
    
    public var securityWarningText: String? {
        if requiresLibraryValidation && !hasGetTaskAllow {
            return "Target enforces Library Validation (CS_REQUIRE_LV). Injection of third-party payloads may be rejected by kernel."
        }
        if isHardenedRuntime && !hasGetTaskAllow {
            return "Target runs with Hardened Runtime without get-task-allow."
        }
        return nil
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: ProcessItem, rhs: ProcessItem) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.path == rhs.path && lhs.arch == rhs.arch
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

// MARK: - Deep Introspection & Process Security Models

public struct ProcessSecurityInfo: Equatable {
    public let csFlags: UInt32
    public let isValid: Bool
    public let isAdHoc: Bool
    public let hasGetTaskAllow: Bool
    public let isRestricted: Bool
    public let requiresLibraryValidation: Bool
    public let isHardenedRuntime: Bool
    public let teamIdentifier: String?
    public let cdHash: String?
    
    public init(csFlags: UInt32, teamIdentifier: String? = nil, cdHash: String? = nil) {
        self.csFlags = csFlags
        self.isValid = (csFlags & 0x00000001) != 0
        self.isAdHoc = (csFlags & 0x00000002) != 0
        self.hasGetTaskAllow = (csFlags & 0x00000004) != 0
        self.isRestricted = (csFlags & 0x00000800) != 0
        self.requiresLibraryValidation = (csFlags & 0x00002000) != 0
        self.isHardenedRuntime = (csFlags & 0x00010000) != 0
        self.teamIdentifier = teamIdentifier
        self.cdHash = cdHash
    }
}

public struct ProcessResourceUsage: Equatable {
    public let residentSize: UInt64
    public let virtualSize: UInt64
    public let threadCount: Int
    public let userCpuTime: TimeInterval
    public let systemCpuTime: TimeInterval
    public let uptimeSeconds: TimeInterval
    public let parentPid: Int32
    public let username: String
    
    public init(
        residentSize: UInt64,
        virtualSize: UInt64,
        threadCount: Int,
        userCpuTime: TimeInterval,
        systemCpuTime: TimeInterval,
        uptimeSeconds: TimeInterval,
        parentPid: Int32,
        username: String
    ) {
        self.residentSize = residentSize
        self.virtualSize = virtualSize
        self.threadCount = threadCount
        self.userCpuTime = userCpuTime
        self.systemCpuTime = systemCpuTime
        self.uptimeSeconds = uptimeSeconds
        self.parentPid = parentPid
        self.username = username
    }
    
    public var formattedRss: String {
        ByteCountFormatter.string(fromByteCount: Int64(residentSize), countStyle: .memory)
    }
    
    public var formattedVirtualSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(virtualSize), countStyle: .memory)
    }
    
    public var formattedUptime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: uptimeSeconds) ?? "\(Int(uptimeSeconds))s"
    }
}

public struct LoadedModule: Identifiable, Hashable {
    public var id: String { "\(baseAddress)_\(path)" }
    public let name: String
    public let path: String
    public let baseAddress: UInt64
    public let size: UInt64
    
    public init(name: String, path: String, baseAddress: UInt64, size: UInt64) {
        self.name = name
        self.path = path
        self.baseAddress = baseAddress
        self.size = size
    }
    
    public var formattedBaseAddress: String {
        String(format: "0x%012llX", baseAddress)
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

public struct DylibSliceInfo: Identifiable, Hashable {
    public var id: String { arch.rawValue }
    public let arch: CpuArch
    public let fileOffset: UInt64
    public let sliceSize: UInt64
    
    public init(arch: CpuArch, fileOffset: UInt64, sliceSize: UInt64) {
        self.arch = arch
        self.fileOffset = fileOffset
        self.sliceSize = sliceSize
    }
}

public struct DylibInspectionResult: Equatable {
    public let filePath: String
    public let fileName: String
    public let installName: String
    public let currentVersion: String
    public let compatibilityVersion: String
    public let slices: [DylibSliceInfo]
    public let dependencies: [String]
    public let rpaths: [String]
    public let isSigned: Bool
    public let isAdHoc: Bool
    public let teamIdentifier: String?
    public let totalFileSize: UInt64
    
    public init(
        filePath: String,
        fileName: String,
        installName: String,
        currentVersion: String,
        compatibilityVersion: String,
        slices: [DylibSliceInfo],
        dependencies: [String],
        rpaths: [String],
        isSigned: Bool,
        isAdHoc: Bool,
        teamIdentifier: String?,
        totalFileSize: UInt64
    ) {
        self.filePath = filePath
        self.fileName = fileName
        self.installName = installName
        self.currentVersion = currentVersion
        self.compatibilityVersion = compatibilityVersion
        self.slices = slices
        self.dependencies = dependencies
        self.rpaths = rpaths
        self.isSigned = isSigned
        self.isAdHoc = isAdHoc
        self.teamIdentifier = teamIdentifier
        self.totalFileSize = totalFileSize
    }
    
    public func isCompatible(with targetArch: CpuArch) -> Bool {
        if targetArch == .unknown { return true }
        return slices.contains { $0.arch == targetArch }
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalFileSize), countStyle: .file)
    }
}

public struct PayloadTelemetry: Decodable, Equatable {
    public let version: String
    public let targetPid: Int32
    public let uptimeSeconds: UInt64
    public let memoryRssBytes: UInt64
    public let whitelistStatus: String
    public let isBooster: Bool
    public let earlyAccess: Bool
    public let cryptoStatus: String
    public let activeHooksCount: Int
    public let scriptsExecutedTotal: UInt64
    public let drawingObjectsCount: Int
    public let hooks: [HookTelemetry]
    public let luaStateStatus: String?
    public init(
        version: String = "0.2.0",
        targetPid: Int32 = 0,
        uptimeSeconds: UInt64 = 0,
        memoryRssBytes: UInt64 = 0,
        whitelistStatus: String = "Offline (Local)",
        isBooster: Bool = true,
        earlyAccess: Bool = true,
        cryptoStatus: String = "Pure Rust Engine (AES/SHA/MD5)",
        activeHooksCount: Int = 0,
        scriptsExecutedTotal: UInt64 = 0,
        drawingObjectsCount: Int = 0,
        hooks: [HookTelemetry] = [],
        luaStateStatus: String? = nil
    ) {
        self.version = version
        self.targetPid = targetPid
        self.uptimeSeconds = uptimeSeconds
        self.memoryRssBytes = memoryRssBytes
        self.whitelistStatus = whitelistStatus
        self.isBooster = isBooster
        self.earlyAccess = earlyAccess
        self.cryptoStatus = cryptoStatus
        self.activeHooksCount = activeHooksCount
        self.scriptsExecutedTotal = scriptsExecutedTotal
        self.drawingObjectsCount = drawingObjectsCount
        self.hooks = hooks
        self.luaStateStatus = luaStateStatus
    }
    
    enum CodingKeys: String, CodingKey {
        case version
        case targetPid = "target_pid"
        case uptimeSeconds = "uptime_seconds"
        case memoryRssBytes = "memory_rss_bytes"
        case whitelistStatus = "whitelist_status"
        case isBooster = "is_booster"
        case earlyAccess = "early_access"
        case cryptoStatus = "crypto_status"
        case activeHooksCount = "active_hooks_count"
        case scriptsExecutedTotal = "scripts_executed_total"
        case drawingObjectsCount = "drawing_objects_count"
        case luaStateStatus = "lua_state_status"
        case hooks
    }
    
    public var formattedMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryRssBytes), countStyle: .memory)
    }
    
    public var formattedUptime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(uptimeSeconds)) ?? "\(uptimeSeconds)s"
    }
}

public struct HookTelemetry: Identifiable, Decodable, Equatable {
    public var id: String { targetAddress }
    public let name: String
    public let targetAddress: String
    public let trampolineAddress: String
    public let isActive: Bool
    public let invocations: UInt64
    
    public init(name: String, targetAddress: String, trampolineAddress: String, isActive: Bool, invocations: UInt64) {
        self.name = name
        self.targetAddress = targetAddress
        self.trampolineAddress = trampolineAddress
        self.isActive = isActive
        self.invocations = invocations
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case targetAddress = "target_address"
        case trampolineAddress = "trampoline_address"
        case isActive = "is_active"
        case invocations
    }
}
