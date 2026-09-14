import Foundation
import Darwin
import Combine

@MainActor
public final class IpcClient: ObservableObject {
    @Published public private(set) var status: IpcStatus = .disconnected
    @Published public var host: String = "127.0.0.1"
    @Published public var portText: String = "5553"
    @Published public private(set) var isBusy: Bool = false
    
    public init() {}
    
    public var port: in_port_t {
        in_port_t(UInt16(portText) ?? 5553)
    }
    
    public func ping() async -> Bool {
        isBusy = true
        let targetHost = host
        let targetPort = port
        
        LogStore.shared.log(.info, "Pinging IPC payload at \(targetHost):\(targetPort)...")
        
        let success = await Task.detached(priority: .userInitiated) {
            Self.sendPing(host: targetHost, port: targetPort)
        }.value
        
        if success {
            status = .connected(port: Int(targetPort))
            LogStore.shared.log(.success, "IPC Payload is ONLINE and responsive at \(targetHost):\(targetPort) (PONG 0x10 received)")
        } else {
            status = .disconnected
            LogStore.shared.log(.warning, "IPC Payload is OFFLINE at \(targetHost):\(targetPort) (connection refused or timed out)")
        }
        
        isBusy = false
        return success
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
        
        var timeout = timeval(tv_sec: timeoutSec, tv_usec: 0)
        _ = setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(host)
        
        let res = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if res < 0 {
            close(sock)
            return nil
        }
        
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
    
    private nonisolated static func sendPing(host: String, port: in_port_t) -> Bool {
        guard let sock = createSocket(host: host, port: port, timeoutSec: 1) else {
            return false
        }
        defer { close(sock) }
        
        // Header: msg_type = 2 (IPC_PING), size = 0
        let header = makeHeader(msgType: 2, size: 0)
        let sent = send(sock, header, header.count, 0)
        guard sent == header.count else { return false }
        
        var responseByte: UInt8 = 0
        let recvd = recv(sock, &responseByte, 1, 0)
        // Expected PONG_BYTE = 0x10
        return recvd == 1 && responseByte == 0x10
    }
    
    private nonisolated static func sendExecute(host: String, port: in_port_t, script: String) -> Bool {
        guard let sock = createSocket(host: host, port: port, timeoutSec: 2) else {
            return false
        }
        defer { close(sock) }
        
        let scriptBytes = [UInt8](script.utf8)
        let header = makeHeader(msgType: 0, size: UInt64(scriptBytes.count))
        
        let headerSent = send(sock, header, header.count, 0)
        guard headerSent == header.count else { return false }
        
        let bodySent = send(sock, scriptBytes, scriptBytes.count, 0)
        return bodySent == scriptBytes.count
    }
    
    private nonisolated static func sendSettingRaw(host: String, port: in_port_t, payload: String) -> Bool {
        guard let sock = createSocket(host: host, port: port, timeoutSec: 2) else {
            return false
        }
        defer { close(sock) }
        
        let payloadBytes = [UInt8](payload.utf8)
        let header = makeHeader(msgType: 1, size: UInt64(payloadBytes.count))
        
        let headerSent = send(sock, header, header.count, 0)
        guard headerSent == header.count else { return false }
        
        let bodySent = send(sock, payloadBytes, payloadBytes.count, 0)
        return bodySent == payloadBytes.count
    }
}
