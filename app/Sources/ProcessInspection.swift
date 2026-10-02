import Foundation
import AppKit
import Darwin

@_silgen_name("csops")
private func darwin_csops(_ pid: pid_t, _ ops: UInt32, _ useraddr: UnsafeMutableRawPointer?, _ usersize: Int) -> Int32

@_silgen_name("proc_regionfilename")
private func darwin_proc_regionfilename(_ pid: Int32, _ address: UInt64, _ buffer: UnsafeMutableRawPointer?, _ buffersize: UInt32) -> Int32

public enum ProcessInspection {
    private static let CS_OPS_STATUS: UInt32 = 0
    private static let CS_OPS_CDHASH: UInt32 = 5
    private static let CS_OPS_TEAMID: UInt32 = 10
    
    // MARK: - Process Security & Code Signing Inspection
    
    public static func fetchSecurity(pid: pid_t) -> ProcessSecurityInfo? {
        guard pid > 0 else { return nil }
        
        var csFlags: UInt32 = 0
        let statusRet = darwin_csops(pid, CS_OPS_STATUS, &csFlags, MemoryLayout<UInt32>.size)
        if statusRet != 0 {
            return nil
        }
        
        // Fetch Team ID if available
        var teamIdBuffer = [CChar](repeating: 0, count: 256)
        var teamId: String? = nil
        let teamRet = darwin_csops(pid, CS_OPS_TEAMID, &teamIdBuffer, teamIdBuffer.count)
        if teamRet == 0 {
            let str = String(cString: teamIdBuffer).trimmingCharacters(in: .whitespacesAndNewlines)
            if !str.isEmpty {
                teamId = str
            }
        }
        
        // Fetch CDHash if available
        var cdHashBuffer = [UInt8](repeating: 0, count: 20)
        var cdHash: String? = nil
        let cdHashRet = darwin_csops(pid, CS_OPS_CDHASH, &cdHashBuffer, cdHashBuffer.count)
        if cdHashRet == 0 {
            cdHash = cdHashBuffer.map { String(format: "%02x", $0) }.joined()
        }
        
        return ProcessSecurityInfo(csFlags: csFlags, teamIdentifier: teamId, cdHash: cdHash)
    }
    
    // MARK: - Process Resource Usage & Metrics
    
    public static func fetchResources(pid: pid_t) -> ProcessResourceUsage? {
        guard pid > 0 else { return nil }
        
        var taskInfo = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let retTask = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskSize)
        
        var bsdInfo = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let retBsd = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize)
        
        guard retTask == taskSize || retBsd == bsdSize else { return nil }
        
        let resident = (retTask == taskSize) ? taskInfo.pti_resident_size : 0
        let virtualSize = (retTask == taskSize) ? taskInfo.pti_virtual_size : 0
        let threadCount = (retTask == taskSize) ? Int(taskInfo.pti_threadnum) : 0
        let userCpu = (retTask == taskSize) ? TimeInterval(taskInfo.pti_total_user) / 1_000_000_000.0 : 0
        let systemCpu = (retTask == taskSize) ? TimeInterval(taskInfo.pti_total_system) / 1_000_000_000.0 : 0
        
        var uptime: TimeInterval = 0
        var parentPid: Int32 = 0
        var username = "system"
        
        if retBsd == bsdSize {
            parentPid = Int32(bsdInfo.pbi_ppid)
            if bsdInfo.pbi_start_tvsec > 0 {
                uptime = max(0, TimeInterval(time(nil) - Int(bsdInfo.pbi_start_tvsec)))
            }
            if let pw = getpwuid(bsdInfo.pbi_uid) {
                username = String(cString: pw.pointee.pw_name)
            } else {
                username = "UID \(bsdInfo.pbi_uid)"
            }
        }
        
        return ProcessResourceUsage(
            residentSize: resident,
            virtualSize: virtualSize,
            threadCount: threadCount,
            userCpuTime: userCpu,
            systemCpuTime: systemCpu,
            uptimeSeconds: uptime,
            parentPid: parentPid,
            username: username
        )
    }
    
    // MARK: - Enumerate Loaded Modules (Dynamic Libraries & Binaries)
    
    public static func enumerateModules(pid: pid_t) -> [LoadedModule] {
        guard pid > 0 else { return [] }
        
        var modules: [LoadedModule] = []
        var seenPaths = Set<String>()
        var address: UInt64 = 0
        var vinfo = proc_regioninfo()
        let vinfoSize = Int32(MemoryLayout<proc_regioninfo>.size)
        var buffer = [CChar](repeating: 0, count: 4096)
        
        var iterationCount = 0
        let maxIterations = 2048 // Circuit breaker for safety
        
        while iterationCount < maxIterations {
            iterationCount += 1
            let ret = proc_pidinfo(pid, PROC_PIDREGIONINFO, address, &vinfo, vinfoSize)
            guard ret == vinfoSize else { break }
            
            buffer.withUnsafeMutableBufferPointer { ptr in
                ptr.initialize(repeating: 0)
            }
            let fnRet = darwin_proc_regionfilename(pid, address, &buffer, UInt32(buffer.count))
            if fnRet > 0 {
                let path = String(cString: buffer)
                if !path.isEmpty && !seenPaths.contains(path) {
                    seenPaths.insert(path)
                    let name = (path as NSString).lastPathComponent
                    modules.append(LoadedModule(
                        name: name,
                        path: path,
                        baseAddress: address,
                        size: UInt64(vinfo.pri_size)
                    ))
                }
            }
            
            let nextAddress = vinfo.pri_address &+ UInt64(vinfo.pri_size)
            if nextAddress <= address || nextAddress == 0 {
                break
            }
            address = nextAddress
        }
        
        return modules.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - Running Application Integration
    
    public static func fetchRunningApplication(pid: pid_t) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: pid)
    }
    
    // MARK: - SIP Status Detection
    
    /// Query System Integrity Protection status via `csrutil status`.
    /// Returns true if SIP debugging restrictions are disabled (safe for task_for_pid on Hardened Runtime).
    public static func isSipDebuggingAllowed() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
        process.arguments = ["status"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            // SIP fully disabled or debugging restriction disabled
            if output.contains("disabled") {
                return true
            }
            // Granular: "Debugging Restrictions: disabled"
            if output.lowercased().contains("debugging restrictions: disabled") {
                return true
            }
            return false
        } catch {
            return false
        }
    }
}
