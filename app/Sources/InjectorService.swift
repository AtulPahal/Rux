import Foundation
import AppKit
import Combine

@MainActor
public final class InjectorService: ObservableObject {
    @Published public private(set) var isInjecting: Bool = false
    @Published public var lastResult: String? = nil
    @Published public var lastSuccess: Bool? = nil
    
    public init() {}
    
    public func resolveRuxBinary() -> String? {
        let fileManager = FileManager.default
        
        // 1. Check Contents/Helpers/rux and Contents/MacOS/rux-cli
        if let macosUrl = Bundle.main.executableURL?.deletingLastPathComponent() {
            let cliPath = macosUrl.appendingPathComponent("rux-cli").path
            if fileManager.isExecutableFile(atPath: cliPath) {
                return cliPath
            }
            let helperPath = macosUrl.deletingLastPathComponent().appendingPathComponent("Helpers/rux").path
            if fileManager.isExecutableFile(atPath: helperPath) {
                return helperPath
            }
        }
        // 2. Check Resources directory
        if let resourceUrl = Bundle.main.resourceURL {
            let path = resourceUrl.appendingPathComponent("rux").path
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        // 3. Check working directory / development paths
        let candidatePaths = [
            "rux",
            "./rux",
            "../rux",
            "../../rux",
            "target/release/rux",
            "../target/release/rux",
            "../../target/release/rux"
        ]
        
        for p in candidatePaths {
            let absPath = (p as NSString).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: absPath) {
                return absPath
            }
        }
        
        return nil
    }
    
    public func resolveDefaultDylib() -> String? {
        let fileManager = FileManager.default
        
        // 1. Check Frameworks in bundle
        if let frameworksUrl = Bundle.main.privateFrameworksURL {
            let p1 = frameworksUrl.appendingPathComponent("exploit.dylib").path
            if fileManager.fileExists(atPath: p1) { return p1 }
            let p2 = frameworksUrl.appendingPathComponent("librux_payload.dylib").path
            if fileManager.fileExists(atPath: p2) { return p2 }
        }
        
        // 2. Check Resources in bundle
        if let resourceUrl = Bundle.main.resourceURL {
            let p1 = resourceUrl.appendingPathComponent("exploit.dylib").path
            if fileManager.fileExists(atPath: p1) { return p1 }
            let p2 = resourceUrl.appendingPathComponent("librux_payload.dylib").path
            if fileManager.fileExists(atPath: p2) { return p2 }
        }
        
        // 3. Check development paths
        let devPaths = [
            "exploit.dylib",
            "./exploit.dylib",
            "../exploit.dylib",
            "../../exploit.dylib",
            "target/release/librux_payload.dylib",
            "../target/release/librux_payload.dylib"
        ]
        
        for p in devPaths {
            let absPath = (p as NSString).expandingTildeInPath
            if fileManager.fileExists(atPath: absPath) {
                return absPath
            }
        }
        
        return nil
    }
    
    public func inject(config: InjectConfig) async {
        guard !isInjecting else { return }
        isInjecting = true
        lastResult = nil
        lastSuccess = nil
        
        LogStore.shared.log(.info, "Starting dynamic library injection workflow...")
        
        guard let ruxBinary = resolveRuxBinary() else {
            let msg = "Rux injection engine binary ('rux') could not be found."
            LogStore.shared.log(.error, msg)
            lastResult = msg
            lastSuccess = false
            isInjecting = false
            return
        }
        
        // Resolve dynamic library path
        var dylibPath = config.targetDylibPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if dylibPath.isEmpty {
            if let defaultDylib = resolveDefaultDylib() {
                dylibPath = defaultDylib
                LogStore.shared.log(.info, "Using bundled payload dylib: \(dylibPath)")
            } else {
                let msg = "No dynamic library selected and no default payload found."
                LogStore.shared.log(.error, msg)
                lastResult = msg
                lastSuccess = false
                isInjecting = false
                return
            }
        }
        
        guard FileManager.default.fileExists(atPath: dylibPath) else {
            let msg = "Dynamic library file does not exist at: \(dylibPath)"
            LogStore.shared.log(.error, msg)
            lastResult = msg
            lastSuccess = false
            isInjecting = false
            return
        }
        
        // Build CLI argument list
        var args: [String] = ["inject", dylibPath]
        
        if let proc = config.targetProcess {
            args.append("-p")
            args.append("\(proc.pid)")
            LogStore.shared.log(.info, "Targeting process: \(proc.name) (PID: \(proc.pid), Arch: \(proc.arch.rawValue))")
        } else if !config.targetPidText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let pidStr = config.targetPidText.trimmingCharacters(in: .whitespacesAndNewlines)
            args.append("-p")
            args.append(pidStr)
            LogStore.shared.log(.info, "Targeting specified PID: \(pidStr)")
        } else if !config.targetNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let nameStr = config.targetNameText.trimmingCharacters(in: .whitespacesAndNewlines)
            args.append("-n")
            args.append(nameStr)
            LogStore.shared.log(.info, "Targeting process name: \(nameStr)")
        } else {
            let msg = "Please specify a target process (PID or process name)."
            LogStore.shared.log(.error, msg)
            lastResult = msg
            lastSuccess = false
            isInjecting = false
            return
        }
        
        args.append("-m")
        args.append(config.dlopenMode.rawValue)
        
        args.append("-t")
        args.append("\(Int(config.timeoutMs))")
        
        if !config.waitCompletion {
            args.append("-w")
        }
        
        if config.verbose {
            args.append("-v")
        }
        
        let useAdmin = config.useAdminPrivileges
        
        let taskResult = await Task.detached(priority: .userInitiated) {
            Self.runCommand(executable: ruxBinary, arguments: args, useAdmin: useAdmin)
        }.value
        
        // Process output
        let (exitCode, stdout, stderr) = taskResult
        let combinedOutput = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        
        for line in combinedOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.contains("Injection confirmed") || trimmed.contains("successfully injected") {
                LogStore.shared.log(.success, trimmed)
            } else if trimmed.contains("[-] Injection Failed") || trimmed.contains("Error:") {
                LogStore.shared.log(.error, trimmed)
            } else if trimmed.contains("[!]") {
                LogStore.shared.log(.warning, trimmed)
            } else {
                LogStore.shared.log(.info, trimmed)
            }
        }
        
        if exitCode == 0 {
            let successMsg = "Injection successfully completed! Exit code 0."
            LogStore.shared.log(.success, successMsg)
            lastResult = successMsg
            lastSuccess = true
        } else {
            let errorMsg = combinedOutput.isEmpty ? "Injection failed with exit code \(exitCode)." : combinedOutput
            lastResult = errorMsg
            lastSuccess = false
        }
        
        isInjecting = false
    }
    
    private nonisolated static func runCommand(
        executable: String,
        arguments: [String],
        useAdmin: Bool
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        if useAdmin {
            // Build escaped shell command for AppleScript
            let escapedArgs = arguments.map { arg in
                "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
            }.joined(separator: " ")
            let fullCommand = "'\(executable)' \(escapedArgs) 2>&1"
            
            let sanitized = fullCommand
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let appleScriptSource = "do shell script \"" + sanitized + "\" with administrator privileges"
            
            var errorDict: NSDictionary?
            if let script = NSAppleScript(source: appleScriptSource) {
                let descriptor = script.executeAndReturnError(&errorDict)
                if let error = errorDict {
                    let errMsg = error[NSAppleScript.errorMessage] as? String ?? "AppleScript execution error"
                    let errNum = error[NSAppleScript.errorNumber] as? Int32 ?? -1
                    // Error -128 is User Canceled
                    if errNum == -128 {
                        return (-128, "", "Privilege escalation canceled by user.")
                    }
                    return (errNum, "", errMsg)
                }
                let output = descriptor.stringValue ?? ""
                return (0, output, "")
            } else {
                return (-1, "", "Failed to compile privilege escalation script.")
            }
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                
                return (process.terminationStatus, stdout, stderr)
            } catch {
                return (-1, "", "Failed to spawn process: \(error.localizedDescription)")
            }
        }
    }
}
