import Foundation
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
            
            // 1. Resolve executable path
            pathBuffer.withUnsafeMutableBufferPointer { ptr in
                _ = proc_pidpath(pid, ptr.baseAddress, UInt32(ptr.count))
            }
            let rawPath = String(cString: pathBuffer)
            let path: String? = rawPath.isEmpty ? nil : rawPath
            
            // 2. Resolve process name
            var name: String = ""
            if let path = path, !path.isEmpty {
                name = (path as NSString).lastPathComponent
            }
            
            if name.isEmpty {
                var bsdInfo = proc_bsdinfo()
                let size = Int32(MemoryLayout<proc_bsdinfo>.size)
                let res = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, size)
                if res == size {
                    let bsdName = withUnsafePointer(to: &bsdInfo.pbi_name) { ptr in
                        ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { cStr in
                            String(cString: cStr)
                        }
                    }
                    if !bsdName.isEmpty {
                        name = bsdName
                    }
                }
            }
            
            if name.isEmpty {
                continue
            }
            
            // 3. Query CPU architecture
            let arch = queryCpuArch(pid: pid)
            
            results.append(ProcessItem(pid: pid, name: name, path: path, arch: arch))
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
    
    private nonisolated static func queryCpuArch(pid: pid_t) -> CpuArch {
        var mib = [Int32](repeating: 0, count: 12)
        var mibLen: size_t = 12
        var cputype: cpu_type_t = 0
        var size = MemoryLayout<cpu_type_t>.size
        
        if sysctlnametomib("sysctl.proc_cputype", &mib, &mibLen) == 0 && mibLen < 12 {
            mib[Int(mibLen)] = pid
            let queryLen = u_int(mibLen + 1)
            if sysctl(&mib, queryLen, &cputype, &size, nil, 0) == 0 {
                // Mach CPU_TYPE_ARM64 = 0x0100000c, CPU_TYPE_X86_64 = 0x01000007
                if cputype == 0x0100000c {
                    return .arm64
                } else if cputype == 0x01000007 {
                    return .x86_64
                }
            }
        }
        
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x86_64
        #else
        return .unknown
        #endif
    }
}
