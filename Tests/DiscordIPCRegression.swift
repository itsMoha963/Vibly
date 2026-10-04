import Darwin
import Foundation

private struct RegressionFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw RegressionFailure(description: message) }
}

private final class FakeDiscord: @unchecked Sendable {
    let path: String
    private let listener: Int32
    private let group = DispatchGroup()
    private var failure: Error?

    init(path: String) throws {
        self.path = path
        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        try check(bytes.count <= MemoryLayout.size(ofValue: address.sun_path), "Test socket path too long")
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try check(bound == 0 && Darwin.listen(listener, 1) == 0, "Cannot open test socket")
    }

    func start() {
        group.enter()
        DispatchQueue.global().async { [self] in
            defer { group.leave() }
            let peer = Darwin.accept(listener, nil, nil)
            defer { Darwin.close(peer) }
            do {
                let handshake = try receive(peer)
                try check(handshake.0 == 0, "Missing handshake")
                try send(peer, payload: ["cmd": "DISPATCH", "evt": "READY", "data": [:]])

                let first = try request(peer)
                let firstAssets = try assets(first)
                try check(firstAssets["large_image"] == "iterm", "Main image mapping is wrong")
                try check(firstAssets["small_image"] == "nvim", "Badge image mapping is wrong")
                try check(firstAssets["large_text"] == "iTerm", "Main hover text is wrong")
                try check(firstAssets["small_text"] == "Neovim", "Badge hover text is wrong")
                // An old error must not be mistaken for this publication's reply.
                try send(peer, payload: ["cmd": "SET_ACTIVITY", "nonce": "old-request",
                                         "evt": "ERROR", "data": ["message": "stale error"]])
                let heartbeat = Data("non-JSON heartbeat".utf8)
                try send(peer, opcode: 3, body: heartbeat)
                let pong = try receive(peer)
                try check(pong.0 == 4 && pong.1 == heartbeat, "Heartbeat was not echoed correctly")
                try acknowledge(peer, request: first, assets: firstAssets)

                let second = try request(peer)
                try check(try assets(second)["small_text"] == "Editing helloworld.cpp", "Updated tooltip was lost")
                try send(peer, payload: ["cmd": "DISPATCH", "evt": "ACTIVITY_JOIN", "data": [:]])
                // A dispatch must not hide the actual rejection.
                try send(peer, payload: ["cmd": "SET_ACTIVITY", "nonce": second["nonce"]!,
                                         "evt": "ERROR", "data": ["message": "test rejection"]])

                let third = try request(peer)
                let thirdAssets = try assets(third)
                try check(thirdAssets["small_text"] == nil, "Cleared tooltip was retained")
                try check(thirdAssets["small_image"] == "nvim", "Clearing text removed the badge")
                try acknowledge(peer, request: third, assets: thirdAssets)

                for _ in 0..<8 {
                    let concurrent = try request(peer)
                    try acknowledge(peer, request: concurrent, assets: try assets(concurrent))
                }
                let clear = try request(peer)
                let args = clear["args"] as? [String: Any]
                try check(args?["activity"] is NSNull, "Clear did not send null activity")
                try send(peer, payload: ["cmd": "SET_ACTIVITY", "nonce": clear["nonce"]!, "data": NSNull()])
            } catch { failure = error }
        }
    }

    func finish() throws {
        try check(group.wait(timeout: .now() + 15) == .success, "Test server timed out")
        if let failure { throw failure }
        Darwin.close(listener)
        try FileManager.default.removeItem(atPath: path)
    }

    private func request(_ peer: Int32) throws -> [String: Any] {
        let frame = try receive(peer)
        try check(frame.0 == 1, "Expected command frame")
        return try JSONSerialization.jsonObject(with: frame.1) as! [String: Any]
    }

    private func assets(_ request: [String: Any]) throws -> [String: String] {
        let args = request["args"] as? [String: Any]
        let activity = args?["activity"] as? [String: Any]
        guard let assets = activity?["assets"] as? [String: String] else {
            throw RegressionFailure(description: "Missing assets")
        }
        return assets
    }

    private func acknowledge(_ peer: Int32, request: [String: Any], assets: [String: String]) throws {
        try send(peer, payload: ["cmd": "SET_ACTIVITY", "nonce": request["nonce"]!,
                                 "data": ["assets": assets]])
    }

    private func receive(_ peer: Int32) throws -> (UInt32, Data) {
        func read(_ count: Int) throws -> Data {
            var data = Data()
            while data.count < count {
                var bytes = [UInt8](repeating: 0, count: count - data.count)
                let readCount = Darwin.read(peer, &bytes, bytes.count)
                try check(readCount > 0, "Peer disconnected")
                data.append(contentsOf: bytes.prefix(readCount))
            }
            return data
        }
        let header = [UInt8](try read(8))
        func number(_ offset: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { $0 | UInt32(header[offset + $1]) << ($1 * 8) }
        }
        return (number(0), try read(Int(number(4))))
    }

    private func send(_ peer: Int32, payload: [String: Any]) throws {
        try send(peer, opcode: 1, body: JSONSerialization.data(withJSONObject: payload))
    }

    private func send(_ peer: Int32, opcode: UInt32, body: Data) throws {
        var frame = Data()
        var op = opcode.littleEndian
        var length = UInt32(body.count).littleEndian
        withUnsafeBytes(of: &op) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(body)
        // Fragment frames to exercise partial reads.
        try frame.withUnsafeBytes { buffer in
            for offset in stride(from: 0, to: frame.count, by: 3) {
                let size = min(3, frame.count - offset)
                try check(Darwin.write(peer, buffer.baseAddress!.advanced(by: offset), size) == size,
                          "Could not send test response")
            }
        }
    }
}

@main
private struct DiscordIPCRegression {
    static func main() throws {
        if CommandLine.arguments.contains("--live") {
            let client = try DiscordIPCClient(applicationID: CommandLine.arguments[2])
            try client.connect()
            var presence = configuration()
            if CommandLine.arguments.count > 3 { presence.largeImageKey = CommandLine.arguments[3] }
            let response = try client.setPresence(presence)
            let data = response["data"] as? [String: Any]
            print(String(data: try JSONSerialization.data(withJSONObject: data?["assets"] ?? [:],
                                                          options: [.sortedKeys]), encoding: .utf8)!)
            client.close()
            return
        }

        let server = try FakeDiscord(path: CommandLine.arguments[1] + "/rpc.sock")
        server.start()
        let client = try DiscordIPCClient(applicationID: "123456789", socketPath: server.path)
        try client.connect()
        var presence = configuration()
        let first = try client.setPresence(presence)
        try check(first["nonce"] != nil, "Did not wait for acknowledged publication")
        try check(client.assetWarning(for: presence, response: first) == nil, "Valid artwork produced a warning")
        var acceptedAssets = (first["data"] as! [String: Any])["assets"] as! [String: String]
        acceptedAssets.removeValue(forKey: "large_image")
        let unresolved: [String: Any] = ["data": ["assets": acceptedAssets]]
        try check(client.assetWarning(for: presence, response: unresolved)?.contains("“iterm”") == true,
                  "An unresolved main image was silently reported as success")
        presence.smallImageText = "Editing helloworld.cpp"
        var rejected = false
        do { try client.setPresence(presence) }
        catch { rejected = error.localizedDescription.contains("test rejection") }
        try check(rejected, "A dispatch falsely acknowledged a rejected tooltip update")
        presence.smallImageText = ""
        try client.setPresence(presence)

        DispatchQueue.concurrentPerform(iterations: 8) { index in
            do {
                var update = configuration()
                update.smallImageText = "Neovim \(index)"
                let response = try client.setPresence(update)
                let data = response["data"] as? [String: Any]
                let echoed = data?["assets"] as? [String: String]
                precondition(echoed?["small_text"] == update.smallImageText, "Concurrent replies mixed up")
            } catch { preconditionFailure(error.localizedDescription) }
        }
        try client.clearPresence()
        client.close()
        try server.finish()
        print("PASS: distinct tooltips, updating/clearing, unresolved assets, stale replies, dispatches, ping/pong, fragmented frames, concurrent publications")
    }

    private static func configuration() -> PresenceConfiguration {
        PresenceConfiguration(activity: "iTerm2", details: "Nvim", state: "coding",
                              showElapsedTime: false, startedAt: nil,
                              largeImageKey: " iterm ", largeImageText: " iTerm ",
                              smallImageKey: " nvim ", smallImageText: " Neovim ")
    }
}
