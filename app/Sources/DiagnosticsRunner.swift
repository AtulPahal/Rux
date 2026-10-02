import Foundation
import AppKit
import Combine

@MainActor
public final class DiagnosticsRunner: ObservableObject {
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var items: [DiagnosticItem] = []
    @Published public private(set) var summary: String = "Ready to run diagnostics."
    @Published public private(set) var allPassed: Bool? = nil
    
    public init() {}
    
    public func runDiagnostics() {
        guard !isRunning else { return }
        isRunning = true
        items = []
        allPassed = nil
        summary = "Running diagnostic suite..."
        
        LogStore.shared.log(.info, "Executing Rux Darwin Mach-O diagnostic test suite...")
        
        let injectorService = InjectorService()
        guard let ruxPath = injectorService.resolveRuxBinary() else {
            let msg = "Rux binary ('rux') could not be found to run tests."
            LogStore.shared.log(.error, msg)
            summary = msg
            allPassed = false
            isRunning = false
            return
        }
        
        Task.detached(priority: .userInitiated) {
            let (exitCode, output) = Self.runDiagnosticsProcess(executable: ruxPath)
            
            var (parsedItems, passCount, failCount) = Self.parseTestOutput(output)
            if parsedItems.isEmpty {
                let errorDetails = output.trimmingCharacters(in: .whitespacesAndNewlines)
                let details = errorDetails.isEmpty ? "Diagnostic process terminated with exit code \(exitCode)." : errorDetails
                parsedItems.append(DiagnosticItem(
                    id: 1,
                    title: "Diagnostic Execution Failure",
                    passed: false,
                    details: details
                ))
                failCount = 1
            }
            
            let finalItems = parsedItems
            let finalPass = passCount
            let finalFail = failCount
            let finalExit = exitCode
            let finalOutput = output
            
            await MainActor.run {
                self.items = finalItems
                let total = finalPass + finalFail
                if total > 0 && finalFail == 0 {
                    self.allPassed = true
                    self.summary = "All \(finalPass) diagnostic tests PASSED successfully!"
                    LogStore.shared.log(.success, "Diagnostics completed: \(finalPass)/\(total) passed.")
                } else if total > 0 {
                    self.allPassed = false
                    self.summary = "Diagnostic failure: \(finalFail) failed, \(finalPass) passed."
                    LogStore.shared.log(.error, "Diagnostics completed: \(finalFail) failed.")
                } else {
                    self.allPassed = false
                    self.summary = "Diagnostics finished with exit code \(finalExit)."
                    LogStore.shared.log(.warning, "Diagnostic output:\n\(finalOutput)")
                }
                self.isRunning = false
            }
        }
    }
    
    private nonisolated static func runDiagnosticsProcess(executable: String) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["test"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            
            var pipeData = Data()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                pipeData = pipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            
            process.waitUntilExit()
            group.wait()
            
            let exitCode = process.terminationStatus
            let output = String(data: pipeData, encoding: .utf8) ?? ""
            return (exitCode, output)
        } catch {
            return (-1, "Error launching diagnostics: \(error.localizedDescription)")
        }
    }
    
    private nonisolated static func parseTestOutput(_ output: String) -> (items: [DiagnosticItem], passed: Int, failed: Int) {
        var items: [DiagnosticItem] = []
        var passed = 0
        var failed = 0
        
        let lines = output.components(separatedBy: "\n")
        var currentId = 1
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("[TEST ") else { continue }
            
            // Format: [TEST 1/5] Host Architecture Detection... PASS (arm64)
            // or: [TEST 2/5] Darwin Process Enumeration (libproc)... PASS (686 active processes)
            let isPass = trimmed.contains("PASS")
            let isFail = trimmed.contains("FAIL")
            
            if isPass { passed += 1 }
            if isFail { failed += 1 }
            
            // Extract title and details
            var title = "Test \(currentId)"
            var details = isPass ? "Passed" : "Failed"
            
            if let closingBracket = trimmed.firstIndex(of: "]") {
                let rest = trimmed[trimmed.index(after: closingBracket)...].trimmingCharacters(in: .whitespaces)
                if let dotsIndex = rest.range(of: "...") {
                    title = String(rest[..<dotsIndex.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let afterDots = String(rest[dotsIndex.upperBound...]).trimmingCharacters(in: .whitespaces)
                    details = afterDots
                } else {
                    title = rest
                }
            }
            
            items.append(DiagnosticItem(id: currentId, title: title, passed: isPass, details: details))
            currentId += 1
        }
        
        return (items, passed, failed)
    }
}
