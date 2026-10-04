import Darwin
import Foundation

enum DiscordConnectionState: Equatable {
    case starting
    case ready
    case unavailable(String)
    case error(String)

    var title: String {
        switch self {
        case .starting: return "Connecting…"
        case .ready: return "Connected"
        case .unavailable(let reason): return reason
        case .error(let reason): return reason
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

enum DiscordPresenceError: LocalizedError {
    case applicationIDMissing
    case unavailable(String)
    case publishFailed(String)
    case clearFailed(String)

    var errorDescription: String? {
        switch self {
        case .applicationIDMissing:
            return "Enter a Discord Application ID before connecting."
        case .unavailable(let message):
            return message
        case .publishFailed(let message):
            return "Discord could not update the presence: \(message)"
        case .clearFailed(let message):
            return "Discord could not clear the presence: \(message)"
        }
    }
}

@MainActor
protocol DiscordPresenceProviding: AnyObject {
    var state: DiscordConnectionState { get }
    func configure(applicationID: String)
    func start() async throws
    /// Returns an asset warning if Discord accepts the activity but omits requested artwork/text.
    func setPresence(_ configuration: PresenceConfiguration) async throws -> String?
    func clearPresence() async throws
}

private enum DiscordIPCError: LocalizedError {
    case invalidApplicationID
    case pipeNotFound
    case connectionFailed(String)
    case notConnected
    case writeFailed(String)
    case readFailed(String)
    case invalidResponse
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidApplicationID:
            return "The Discord Application ID is invalid."
        case .pipeNotFound:
            return "Discord's local RPC pipe was not found. Is Discord running?"
        case .connectionFailed(let message):
            return "Could not connect to Discord: \(message)"
        case .notConnected:
            return "The Discord RPC connection is not open."
        case .writeFailed(let message):
            return "Could not send data to Discord: \(message)"
        case .readFailed(let message):
            return "Could not read Discord's response: \(message)"
        case .invalidResponse:
            return "Discord returned an invalid RPC response."
        case .rejected(let message):
            return "Discord rejected the RPC request: \(message)"
        }
    }
}

/// Native macOS client for Discord's desktop IPC protocol.
/// Frames contain an 8-byte little-endian header followed by JSON.
final class DiscordIPCClient: @unchecked Sendable {
    private let applicationID: String
    private let socketPath: String?
    private let ioLock = NSRecursiveLock()
    private var fileDescriptor: Int32 = -1

    init(applicationID: String, socketPath: String? = nil) throws {
        let trimmed = applicationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) else {
            throw DiscordIPCError.invalidApplicationID
        }
        self.applicationID = trimmed
        self.socketPath = socketPath
    }

    deinit {
        close()
    }

    func connect() throws {
        ioLock.lock()
        defer { ioLock.unlock() }
        close()

        guard let pipe = socketPath ?? Self.findPipe() else {
            throw DiscordIPCError.pipeNotFound
        }

        fileDescriptor = try Self.openUnixSocket(at: pipe)

        do {
            let response = try request(
                opcode: 0,
                payload: ["v": 1, "client_id": applicationID]
            )

            if let event = response["evt"] as? String, event == "ERROR" {
                throw DiscordIPCError.rejected(Self.message(from: response))
            }
        } catch {
            close()
            throw error
        }
    }

    @discardableResult
    func setPresence(_ configuration: PresenceConfiguration) throws -> [String: Any] {
        ioLock.lock()
        defer { ioLock.unlock() }
        guard fileDescriptor >= 0 else { throw DiscordIPCError.notConnected }

        var activity: [String: Any] = [
            "name": configuration.trimmedActivity,
            "type": 0
        ]

        let details = configuration.details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !details.isEmpty { activity["details"] = details }

        let state = configuration.state.trimmingCharacters(in: .whitespacesAndNewlines)
        if !state.isEmpty { activity["state"] = state }

        if configuration.showElapsedTime, let startedAt = configuration.startedAt {
            activity["timestamps"] = [
                "start": Int(startedAt.timeIntervalSince1970 * 1_000)
            ]
        }

        var assets: [String: Any] = [:]
        if let key = configuration.largeImageKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            assets["large_image"] = key
            if let text = configuration.largeImageText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                assets["large_text"] = text
            }
        }
        if let key = configuration.smallImageKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            assets["small_image"] = key
            if let text = configuration.smallImageText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                assets["small_text"] = text
            }
        }
        if !assets.isEmpty {
            activity["assets"] = assets
        }

        let response = try request(
            opcode: 1,
            payload: [
                "cmd": "SET_ACTIVITY",
                "args": [
                    "pid": Int(ProcessInfo.processInfo.processIdentifier),
                    "activity": activity
                ],
                "nonce": UUID().uuidString
            ]
        )

        try validate(response)
        return response
    }

    func assetWarning(for configuration: PresenceConfiguration, response: [String: Any]) -> String? {
        guard let activity = response["data"] as? [String: Any] else { return nil }
        let assets = activity["assets"] as? [String: Any] ?? [:]
        var warnings: [String] = []
        for (key, imageField, text, textField, label) in [
            (configuration.largeImageKey, "large_image", configuration.largeImageText, "large_text", "main"),
            (configuration.smallImageKey, "small_image", configuration.smallImageText, "small_text", "badge")
        ] {
            guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { continue }
            guard let resolved = assets[imageField] as? String, !resolved.isEmpty else {
                warnings.append("Discord could not resolve the \(label) image key “\(key)” for Application ID \(applicationID). Check the asset key in this application's Developer Portal.")
                continue
            }
            if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
               assets[textField] as? String != text {
                warnings.append("Discord did not return the requested \(label) image hover text. Apply the images again.")
            }
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }

    func clearPresence() throws {
        ioLock.lock()
        defer { ioLock.unlock() }
        guard fileDescriptor >= 0 else { throw DiscordIPCError.notConnected }

        let response = try request(
            opcode: 1,
            payload: [
                "cmd": "SET_ACTIVITY",
                "args": [
                    "pid": Int(ProcessInfo.processInfo.processIdentifier),
                    "activity": NSNull()
                ],
                "nonce": UUID().uuidString
            ]
        )

        try validate(response)
    }

    func close() {
        ioLock.lock()
        defer { ioLock.unlock() }
        guard fileDescriptor >= 0 else { return }

        let descriptor = fileDescriptor
        _ = try? sendFrame(opcode: 2, payload: [:])
        fileDescriptor = -1
        _ = Darwin.shutdown(descriptor, SHUT_RDWR)
        _ = Darwin.close(descriptor)
    }

    private func request(opcode: UInt32, payload: [String: Any]) throws -> [String: Any] {
        try sendFrame(opcode: opcode, payload: payload)
        let nonce = payload["nonce"] as? String
        while true {
            let frame = try readFrame()
            if frame.opcode == 3 {
                try sendFrame(opcode: 4, body: frame.body)
                continue
            }
            guard let response = try JSONSerialization.jsonObject(with: frame.body) as? [String: Any] else {
                throw DiscordIPCError.invalidResponse
            }
            if frame.opcode == 2 {
                throw DiscordIPCError.rejected(Self.message(from: response))
            }
            guard frame.opcode == 1 else { throw DiscordIPCError.invalidResponse }
            if let nonce {
                // Dispatches and replies to older requests are not acknowledgements.
                guard response["nonce"] as? String == nonce else { continue }
                guard response["cmd"] as? String == payload["cmd"] as? String else {
                    throw DiscordIPCError.invalidResponse
                }
            } else {
                guard ["READY", "ERROR"].contains(response["evt"] as? String ?? "") else { continue }
            }
            return response
        }
    }

    @discardableResult
    private func sendFrame(opcode: UInt32, payload: [String: Any]) throws -> Bool {
        guard fileDescriptor >= 0 else { throw DiscordIPCError.notConnected }

        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw DiscordIPCError.writeFailed(error.localizedDescription)
        }

        return try sendFrame(opcode: opcode, body: jsonData)
    }

    @discardableResult
    private func sendFrame(opcode: UInt32, body: Data) throws -> Bool {
        var frame = Data()
        var littleEndianOpcode = opcode.littleEndian
        var littleEndianLength = UInt32(body.count).littleEndian
        withUnsafeBytes(of: &littleEndianOpcode) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: &littleEndianLength) { frame.append(contentsOf: $0) }
        frame.append(body)

        var offset = 0
        do {
            try frame.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                while offset < frame.count {
                    let result = Darwin.write(fileDescriptor, baseAddress.advanced(by: offset), frame.count - offset)
                    if result < 0 && errno == EINTR { continue }
                    guard result > 0 else {
                        throw DiscordIPCError.writeFailed(String(cString: strerror(errno)))
                    }
                    offset += result
                }
            }
        } catch let error as DiscordIPCError {
            throw error
        } catch {
            throw DiscordIPCError.writeFailed(error.localizedDescription)
        }

        return true
    }

    private func readFrame() throws -> (opcode: UInt32, body: Data) {
        let header = try readExactly(8)
        let bytes = [UInt8](header)
        let opcode = Self.uint32(from: bytes, offset: 0)
        let length = Int(Self.uint32(from: bytes, offset: 4))
        guard length <= 1_048_576 else { throw DiscordIPCError.invalidResponse }
        let body = try readExactly(length)
        return (opcode, body)
    }

    private func readExactly(_ count: Int) throws -> Data {
        guard fileDescriptor >= 0 else { throw DiscordIPCError.notConnected }

        var result = Data()
        result.reserveCapacity(count)

        while result.count < count {
            var buffer = [UInt8](repeating: 0, count: count - result.count)
            let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(fileDescriptor, rawBuffer.baseAddress, rawBuffer.count)
            }
            if bytesRead < 0 && errno == EINTR { continue }
            if bytesRead == 0 { throw DiscordIPCError.notConnected }
            guard bytesRead > 0 else {
                throw DiscordIPCError.readFailed(String(cString: strerror(errno)))
            }

            result.append(contentsOf: buffer.prefix(bytesRead))
        }

        return result
    }

    private func validate(_ response: [String: Any]) throws {
        if let event = response["evt"] as? String, event == "ERROR" {
            throw DiscordIPCError.rejected(Self.message(from: response))
        }
    }

    private static func message(from response: [String: Any]) -> String {
        if let data = response["data"] as? [String: Any], let message = data["message"] as? String {
            return message
        }
        return "Unknown error"
    }

    private static func uint32(from bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func findPipe() -> String? {
        var basePaths: [String] = []
        if let temporaryDirectory = ProcessInfo.processInfo.environment["TMPDIR"] {
            basePaths.append(temporaryDirectory)
        }
        basePaths.append(FileManager.default.temporaryDirectory.path)
        basePaths.append("/tmp")

        for basePath in basePaths {
            for index in 0..<10 {
                let candidate = (basePath as NSString).appendingPathComponent("discord-ipc-\(index)")
                if FileManager.default.fileExists(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func openUnixSocket(at path: String) throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw DiscordIPCError.connectionFailed(String(cString: strerror(errno)))
        }

        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        var noSigPipe: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8) + [0]
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= pathCapacity else {
            _ = Darwin.close(descriptor)
            throw DiscordIPCError.connectionFailed("The RPC socket path is too long.")
        }

        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            for (index, byte) in pathBytes.enumerated() {
                rawBuffer[index] = byte
            }
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            let message = String(cString: strerror(errno))
            _ = Darwin.close(descriptor)
            throw DiscordIPCError.connectionFailed(message)
        }

        return descriptor
    }
}

@MainActor
final class DiscordPresenceService: DiscordPresenceProviding {
    private(set) var state: DiscordConnectionState = .unavailable("Application ID required")

    private var applicationID = ""
    private var client: DiscordIPCClient?
    private let ipcQueue = DispatchQueue(label: "com.vibly.discord-ipc")

    func configure(applicationID: String) {
        let trimmed = applicationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != self.applicationID else { return }

        if let previousClient = client {
            ipcQueue.async { previousClient.close() }
        }
        client = nil
        self.applicationID = trimmed
        state = trimmed.isEmpty ? .unavailable("Application ID required") : .unavailable("Not connected")
    }

    func start() async throws {
        guard !applicationID.isEmpty else {
            state = .unavailable("Application ID required")
            throw DiscordPresenceError.applicationIDMissing
        }

        state = .starting
        let applicationID = self.applicationID

        do {
            let connectedClient = try await performIPC {
                let client = try DiscordIPCClient(applicationID: applicationID)
                try client.connect()
                return client
            }

            if let previousClient = client {
                ipcQueue.async { previousClient.close() }
            }
            client = connectedClient
            state = .ready
        } catch {
            client = nil
            state = .unavailable("Discord unavailable")
            throw DiscordPresenceError.unavailable(error.localizedDescription)
        }
    }

    func setPresence(_ configuration: PresenceConfiguration) async throws -> String? {
        guard configuration.validationError == nil else {
            throw DiscordPresenceError.publishFailed("The presence is invalid.")
        }

        let connectedClient = try await connectedClient()
        do {
            return try await performIPC {
                let response = try connectedClient.setPresence(configuration)
                return connectedClient.assetWarning(for: configuration, response: response)
            }
        } catch {
            state = .unavailable("Discord unavailable")
            throw DiscordPresenceError.publishFailed(error.localizedDescription)
        }
    }

    func clearPresence() async throws {
        let connectedClient = try await connectedClient()
        do {
            try await performIPC {
                try connectedClient.clearPresence()
            }
        } catch {
            state = .unavailable("Discord unavailable")
            throw DiscordPresenceError.clearFailed(error.localizedDescription)
        }
    }

    private func connectedClient() async throws -> DiscordIPCClient {
        if let client, state.isReady {
            return client
        }

        try await start()
        guard let client else {
            throw DiscordPresenceError.unavailable("Discord unavailable")
        }
        return client
    }

    private func performIPC<Result: Sendable>(
        _ operation: @escaping @Sendable () throws -> Result
    ) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            ipcQueue.async {
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}
