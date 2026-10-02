import Foundation
import AppKit
import Darwin
import Combine

@MainActor
public final class ProcessScanner: ObservableObject {
    @Published public private(set) var processes: [ProcessItem] = []
    @Published public var searchText: String = ""
    @Published public var selectedArchFilter: String = "All"
    @Published public private(set) var isScanning: Bool = false
    
    public init() {
        refresh()
    }
    
    public var filteredProcesses: [ProcessItem] {
        processes.filter { proc in
            let matchesSearch: Bool
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matchesSearch = true
            } else {
                let query = searchText.lowercased()
                let pidMatches = String(proc.pid).contains(query)
                let nameMatches = proc.name.lowercased().contains(query)
                let pathMatches = proc.path?.lowercased().contains(query) ?? false
                matchesSearch = pidMatches || nameMatches || pathMatches
            }
            
            let matchesArch: Bool
            if selectedArchFilter == "All" {
                matchesArch = true
            } else {
                matchesArch = proc.arch.rawValue == selectedArchFilter
            }
            
            return matchesSearch && matchesArch
        }
    }
    
    public func refresh() {
        guard !isScanning else { return }
        isScanning = true
        
        Task.detached(priority: .userInitiated) {
            let scanned = Self.enumerateProcesses()
            await MainActor.run {
                self.processes = scanned
                self.isScanning = false
            }
        }
    }
    
    public func refreshAsync() async {
        isScanning = true
        let scanned = await Task.detached(priority: .userInitiated) {
            Self.enumerateProcesses()
        }.value
        self.processes = scanned
        self.isScanning = false
    }
    
    private nonisolated static func enumerateProcesses() -> [ProcessItem] {
        let pidsBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard pidsBytes > 0 else { return [] }
        
        let count = Int(pidsBytes) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: count)
        let actualBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, pidsBytes)
        guard actualBytes > 0 else { return [] }
        
        let actualCount = Int(actualBytes) / MemoryLayout<pid_t>.size
        var results: [ProcessItem] = []
        results.reserveCapacity(actualCount)
        
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        
        for i in 0..<actualCount {
            let pid = pids[i]
            guard pid > 0 else { continue }
            
            // 1. Resolve executable path with clean buffer
            pathBuffer.withUnsafeMutableBufferPointer { ptr in
                ptr.initialize(repeating: 0)
            }
            let pathRet = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let path: String?
            if pathRet > 0 {
                let rawPath = String(cString: pathBuffer).trimmingCharacters(in: .whitespacesAndNewlines)
                path = rawPath.isEmpty ? nil : rawPath
            } else {
                path = nil
            }
            
            // 2. Resolve process name safely
            var name: String = ""
            if let path = path, !path.isEmpty {
                name = (path as NSString).lastPathComponent
            }
            
            if name.isEmpty {
                var bsdInfo = proc_bsdinfo()
                let size = Int32(MemoryLayout<proc_bsdinfo>.size)
                let res = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, size)
                if res == size {
                    let bsdName = withUnsafeBytes(of: &bsdInfo.pbi_name) { rawPtr -> String in
                        let bytes = rawPtr.prefix(Int(MAXCOMLEN))
                        let nullIdx = bytes.firstIndex(of: 0) ?? bytes.endIndex
                        return String(decoding: bytes[..<nullIdx], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if !bsdName.isEmpty {
                        name = bsdName
                    }
                }
            }
            
            if name.isEmpty {
                continue
            }
            
            // 3. Query CPU architecture with cached MIB
            let arch = queryCpuArch(pid: pid)
            
            // 4. Check Running Application and Code Sign security flags
            var bundleId: String? = nil
            if let app = NSRunningApplication(processIdentifier: pid) {
                bundleId = app.bundleIdentifier
                if let localized = app.localizedName, !localized.isEmpty {
                    name = localized
                }
            }
            
            let sec = ProcessInspection.fetchSecurity(pid: pid)
            let isHardened = sec?.isHardenedRuntime ?? false
            let reqLV = sec?.requiresLibraryValidation ?? false
            let getTask = sec?.hasGetTaskAllow ?? false
            
            results.append(ProcessItem(
                pid: pid,
                name: name,
                path: path,
                arch: arch,
                bundleIdentifier: bundleId,
                isHardenedRuntime: isHardened,
                requiresLibraryValidation: reqLV,
                hasGetTaskAllow: getTask
            ))
        }
        
        // Sort alphabetically by name, then by PID
        return results.sorted { a, b in
            let c = a.name.localizedCaseInsensitiveCompare(b.name)
            if c == .orderedSame {
                return a.pid < b.pid
            }
            return c == .orderedAscending
        }
    }
    
    private nonisolated static let cachedMibInfo: (mib: [Int32], len: Int)? = {
        var mib = [Int32](repeating: 0, count: 12)
        var mibLen: size_t = 12
        if sysctlnametomib("sysctl.proc_cputype", &mib, &mibLen) == 0 && mibLen < 11 {
            return (mib, Int(mibLen))
        }
        return nil
    }()
    
    private nonisolated static func queryCpuArch(pid: pid_t) -> CpuArch {
        if let info = cachedMibInfo {
            var mib = info.mib
            mib[info.len] = pid
            var cputype: cpu_type_t = 0
            var size = MemoryLayout<cpu_type_t>.size
            let queryLen = u_int(info.len + 1)
            if sysctl(&mib, queryLen, &cputype, &size, nil, 0) == 0 {
                // Mach CPU_TYPE_ARM64 = 0x0100000c, CPU_TYPE_X86_64 = 0x01000007
                if cputype == 0x0100000c {
                    return .arm64
                } else if cputype == 0x01000007 {
                    return .x86_64
                }
            }
        }
        return .unknown
    }
}
