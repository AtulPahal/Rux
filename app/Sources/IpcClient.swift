import Foundation
import Darwin
import Combine

@MainActor
public final class IpcClient: ObservableObject {
    @Published public private(set) var status: IpcStatus = .disconnected
    @Published public var host: String = "127.0.0.1"
    @Published public var portText: String = "5553"
    @Published public private(set) var isBusy: Bool = false
    @Published public private(set) var latestTelemetry: PayloadTelemetry? = nil
    public init() {}
    
    public var port: in_port_t {
        in_port_t(UInt16(portText) ?? 5553)
    }
    
    public func ping() async -> Bool {
        isBusy = true
        let targetHost = host
        let targetPort = port
        
        LogStore.shared.log(.info, "Pinging IPC payload at \(targetHost):\(targetPort)...")
        
        var success = await Task.detached(priority: .userInitiated) {
            Self.sendPing(host: targetHost, port: targetPort)
        }.value
        
        var connectedPort = targetPort
        // Auto-probe fallback if default 5553 failed
        if !success && targetPort == 5553 {
            for probePort in 5554...5563 {
                let p = in_port_t(probePort)
                let ok = await Task.detached(priority: .userInitiated) {
                    Self.sendPing(host: targetHost, port: p)
                }.value
                if ok {
                    success = true
                    connectedPort = p
                    self.portText = "\(p)"
                    break
                }
            }
        }
        
        if success {
            status = .connected(port: Int(connectedPort))
            LogStore.shared.log(.success, "IPC Payload is ONLINE and responsive at \(targetHost):\(connectedPort) (PONG 0x10 received)")
            // Auto-fetch telemetry after ping
            _ = await fetchTelemetry()
        } else {
            status = .disconnected
            LogStore.shared.log(.warning, "IPC Payload is OFFLINE at \(targetHost):\(targetPort) (connection refused or timed out)")
        }
        
        isBusy = false
        return success
    }
    
    public func fetchTelemetry() async -> PayloadTelemetry? {
        let targetHost = host
        let targetPort = port
        
        let telemetry = await Task.detached(priority: .userInitiated) {
            Self.queryTelemetry(host: targetHost, port: targetPort)
        }.value
        
        if let t = telemetry {
            self.latestTelemetry = t
            LogStore.shared.log(.info, "Telemetry fetched: target PID \(t.targetPid), uptime \(t.formattedUptime), memory \(t.formattedMemory)")
        }
        return telemetry
    }
    
    public func executeScript(_ script: String) async -> Bool {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            LogStore.shared.log(.warning, "Cannot execute empty script.")
            return false
        }
        
        isBusy = true
        let targetHost = host
        let targetPort = port
        
        LogStore.shared.log(.info, "Dispatching script (\(script.utf8.count) bytes) to IPC payload...")
        
        let success = await Task.detached(priority: .userInitiated) {
            Self.sendExecute(host: targetHost, port: targetPort, script: script)
        }.value
        
        if success {
            status = .connected(port: Int(targetPort))
            LogStore.shared.log(.success, "Script successfully delivered to target payload for execution!")
        } else {
            status = .disconnected
            LogStore.shared.log(.error, "Failed to deliver script to payload at \(targetHost):\(targetPort). Is payload injected?")
        }
        
        isBusy = false
        return success
    }
    
    public func sendSetting(key: String, value: String) async -> Bool {
        isBusy = true
        let targetHost = host
        let targetPort = port
        let payload = "\(key) \(value)"
        
        LogStore.shared.log(.info, "Updating IPC setting -> \(key): \(value)...")
        
        let success = await Task.detached(priority: .userInitiated) {
            Self.sendSettingRaw(host: targetHost, port: targetPort, payload: payload)
        }.value
        
        if success {
            status = .connected(port: Int(targetPort))
            LogStore.shared.log(.success, "Setting updated successfully!")
        } else {
            status = .disconnected
            LogStore.shared.log(.error, "Failed to update setting over IPC.")
        }
        
        isBusy = false
        return success
    }
    
    // MARK: - POSIX Socket Networking
    
    private nonisolated static func createSocket(host: String, port: in_port_t, timeoutSec: Int = 2) -> Int32? {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        
        // 1. Prevent SIGPIPE crash
        var nosigpipe: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
        
        // 2. Resolve host safely
        var resolvedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedHost == "localhost" || resolvedHost.isEmpty {
            resolvedHost = "127.0.0.1"
        }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        if inet_pton(AF_INET, resolvedHost, &addr.sin_addr) <= 0 {
            close(sock)
            return nil
        }
        
        // 3. Non-blocking connect with poll timeout
        let origFlags = fcntl(sock, F_GETFL, 0)
        if origFlags != -1 {
            _ = fcntl(sock, F_SETFL, origFlags | O_NONBLOCK)
        }
        
        let connRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if connRes < 0 && errno != EINPROGRESS {
            close(sock)
            return nil
        }
        
        if connRes != 0 {
            var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
            let pollRet = poll(&pfd, 1, Int32(timeoutSec * 1000))
            if pollRet <= 0 {
                close(sock)
                return nil
            }
            
            var soError: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            if getsockopt(sock, SOL_SOCKET, SO_ERROR, &soError, &len) < 0 || soError != 0 {
                close(sock)
                return nil
            }
        }
        
        // Restore blocking flags
        if origFlags != -1 {
            _ = fcntl(sock, F_SETFL, origFlags)
        }
        
        var timeout = timeval(tv_sec: timeoutSec, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        return sock
    }
    
    private nonisolated static func makeHeader(msgType: UInt8, size: UInt64) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 16)
        header[0] = msgType
        var leSize = size.littleEndian
        withUnsafeBytes(of: &leSize) { rawBytes in
            for i in 0..<8 {
                header[8 + i] = rawBytes[i]
            }
        }
        return header
    }
    
    private nonisolated static func sendAll(sock: Int32, data: [UInt8]) -> Bool {
        var totalSent = 0
        while totalSent < data.count {
            let remaining = data.count - totalSent
            let sent = data.withUnsafeBytes { ptr in
                send(sock, ptr.baseAddress! + totalSent, remaining, 0)
            }
            if sent <= 0 { return false }
            totalSent += sent
        }
        return true
    }
    
    private nonisolated static func recvExact(sock: Int32, count: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: count)
        var totalRecvd = 0
        while totalRecvd < count {
            let remaining = count - totalRecvd
            let recvd = buffer.withUnsafeMutableBytes { ptr in
                recv(sock, ptr.baseAddress! + totalRecvd, remaining, 0)
            }
            if recvd <= 0 { return nil }
            totalRecvd += recvd
        }
        return buffer
    }
    
    private nonisolated static func sendPing(host: String, port: in_port_t) -> Bool {
        guard let sock = createSocket(host: host, port: port, timeoutSec: 1) else {
            return false
        }
        defer { close(sock) }
        
        let header = makeHeader(msgType: 2, size: 0)
        guard sendAll(sock: sock, data: header) else { return false }
        
        var responseByte: UInt8 = 0
        let recvd = recv(sock, &responseByte, 1, 0)
        return recvd == 1 && responseByte == 0x10
    }
    
    private nonisolated static func sendExecute(host: String, port: in_port_t, script: String) -> Bool {
        guard let sock = createSocket(host: host, port: port, timeoutSec: 2) else {
            return false
        }
        defer { close(sock) }
        
        let scriptBytes = [UInt8](script.utf8)
        let header = makeHeader(msgType: 0, size: UInt64(scriptBytes.count))
        
        guard sendAll(sock: sock, data: header) else { return false }
        return sendAll(sock: sock, data: scriptBytes)
    }
    
    private nonisolated static func sendSettingRaw(host: String, port: in_port_t, payload: String) -> Bool {
        guard let sock = createSocket(host: host, port: port, timeoutSec: 2) else {
            return false
        }
        defer { close(sock) }
        
        let payloadBytes = [UInt8](payload.utf8)
        let header = makeHeader(msgType: 1, size: UInt64(payloadBytes.count))
        
        guard sendAll(sock: sock, data: header) else { return false }
        return sendAll(sock: sock, data: payloadBytes)
    }
    
    private nonisolated static func queryTelemetry(host: String, port: in_port_t) -> PayloadTelemetry? {
        guard let sock = createSocket(host: host, port: port, timeoutSec: 2) else {
            return nil
        }
        defer { close(sock) }
        
        // Header: msg_type = 3 (IPC_MSG_TELEMETRY), size = 0
        let header = makeHeader(msgType: 3, size: 0)
        guard sendAll(sock: sock, data: header) else { return nil }
        
        guard let respHeader = recvExact(sock: sock, count: 16) else { return nil }
        guard respHeader[0] == 3 else { return nil }
        
        var size: UInt64 = 0
        withUnsafeMutableBytes(of: &size) { rawBytes in
            for i in 0..<8 {
                rawBytes[i] = respHeader[8 + i]
            }
        }
        size = UInt64(littleEndian: size)
        guard size > 0 && size < 1024 * 1024 else { return nil }
        
        guard let jsonBytes = recvExact(sock: sock, count: Int(size)) else { return nil }
        let data = Data(jsonBytes)
        return try? JSONDecoder().decode(PayloadTelemetry.self, from: data)
    }
}
