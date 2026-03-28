import Vapor
import Foundation

/// Connection endpoint for a WebSocket relay.
struct ProxyEndpoint: Sendable {
    let vmID: UUID
    let channel: DisplayChannel
}

/// Which channel the WebSocket belongs to.
enum DisplayChannel: String, Sendable {
    case display
    case control
}

/// Relays WebSocket frames between the iOS client and the VM host.
/// In production, the "host" side would be a real WebSocket connection to the Apple Silicon host agent.
/// In simulation mode, we echo display frames and acknowledge control messages.
actor DisplayProxyService {
    /// Active client connections: (vmID, channel) → WebSocket.
    private var clientSockets: [String: WebSocket] = [:]

    /// Simulated host connections (in reality these would be maintained to actual hosts).
    private var hostSockets: [String: WebSocket] = [:]

    private func key(vmID: UUID, channel: DisplayChannel) -> String {
        "\(vmID.uuidString):\(channel.rawValue)"
    }

    /// Register a client WebSocket and begin relaying.
    func registerClient(vmID: UUID, channel: DisplayChannel, ws: WebSocket, app: Application) {
        let k = key(vmID: vmID, channel: channel)

        // Close any existing connection for this VM + channel
        if let existing = clientSockets[k] {
            try? existing.close().wait()
        }
        clientSockets[k] = ws

        app.logger.info("DisplayProxy: client connected for \(k)")
    }

    /// Remove a client connection.
    func removeClient(vmID: UUID, channel: DisplayChannel) {
        let k = key(vmID: vmID, channel: channel)
        clientSockets.removeValue(forKey: k)
    }

    /// Forward a text frame from client to host (or simulate response).
    func relayTextFromClient(vmID: UUID, channel: DisplayChannel, text: String, app: Application) {
        let k = key(vmID: vmID, channel: channel)

        if let hostWS = hostSockets[k] {
            // Production path: forward to host
            hostWS.send(text)
        } else {
            // Simulation: echo an acknowledgement back to the client
            if channel == .control, let clientWS = clientSockets[k] {
                let ack = """
                {"type":"ack","original":\(text),"timestamp":\(Date().timeIntervalSince1970)}
                """
                clientWS.send(ack)
            }
        }
    }

    /// Forward a binary frame from client to host (or simulate response).
    func relayBinaryFromClient(vmID: UUID, channel: DisplayChannel, data: ByteBuffer, app: Application) {
        let k = key(vmID: vmID, channel: channel)

        if let hostWS = hostSockets[k] {
            hostWS.send(raw: data.readableBytesView, opcode: .binary)
        }
        // In simulation mode, binary frames from client (e.g., input data) are simply consumed.
    }

    /// Forward a text frame from host to client.
    func relayTextFromHost(vmID: UUID, channel: DisplayChannel, text: String) {
        let k = key(vmID: vmID, channel: channel)
        clientSockets[k]?.send(text)
    }

    /// Forward a binary frame from host to client (display frames).
    func relayBinaryFromHost(vmID: UUID, channel: DisplayChannel, data: ByteBuffer) {
        let k = key(vmID: vmID, channel: channel)
        clientSockets[k]?.send(raw: data.readableBytesView, opcode: .binary)
    }

    /// Disconnect all sockets for a VM.
    func disconnectAll(vmID: UUID) {
        for channel in [DisplayChannel.display, .control] {
            let k = key(vmID: vmID, channel: channel)
            if let ws = clientSockets.removeValue(forKey: k) {
                try? ws.close().wait()
            }
            if let ws = hostSockets.removeValue(forKey: k) {
                try? ws.close().wait()
            }
        }
    }

    /// Number of active client connections (for monitoring).
    func activeConnectionCount() -> Int {
        clientSockets.count
    }
}
