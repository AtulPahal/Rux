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
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ruxPath)
            process.arguments = ["test"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            var output = ""
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                output = String(data: data, encoding: .utf8) ?? ""
            } catch {
                output = "Error launching diagnostics: \(error.localizedDescription)"
            }
            
            let (parsedItems, passCount, failCount) = Self.parseTestOutput(output)
            let exitCode = process.terminationStatus
            let capturedOutput = output
            
            await MainActor.run {
                self.items = parsedItems
                let total = passCount + failCount
                if total > 0 && failCount == 0 {
                    self.allPassed = true
                    self.summary = "All \(passCount) diagnostic tests PASSED successfully!"
                    LogStore.shared.log(.success, "Diagnostics completed: \(passCount)/\(total) passed.")
                } else if total > 0 {
                    self.allPassed = false
                    self.summary = "Diagnostic failure: \(failCount) failed, \(passCount) passed."
                    LogStore.shared.log(.error, "Diagnostics completed: \(failCount) failed.")
                } else {
                    self.allPassed = false
                    self.summary = "Diagnostics finished with exit code \(exitCode)."
                    LogStore.shared.log(.warning, "Diagnostic output:\n\(capturedOutput)")
                }
                self.isRunning = false
            }
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
