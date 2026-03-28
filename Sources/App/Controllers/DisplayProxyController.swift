import Vapor
import Fluent

/// WebSocket relay for VM display and control streams between the iOS client and the host.
struct DisplayProxyController: RouteCollection {
    let displayProxy: DisplayProxyService
    let instanceManager: InstanceManager

    func boot(routes: any RoutesBuilder) throws {
        let vms = routes.grouped("vms", ":vmID")
        vms.webSocket("display", onUpgrade: handleDisplay)
        vms.webSocket("control", onUpgrade: handleControl)
    }

    // MARK: - Display WebSocket

    @Sendable
    func handleDisplay(req: Request, ws: WebSocket) async {
        await handleWebSocket(req: req, ws: ws, channel: .display)
    }

    // MARK: - Control WebSocket

    @Sendable
    func handleControl(req: Request, ws: WebSocket) async {
        await handleWebSocket(req: req, ws: ws, channel: .control)
    }

    // MARK: - Shared WebSocket Handler

    private func handleWebSocket(req: Request, ws: WebSocket, channel: DisplayChannel) async {
        do {
            // Authenticate via query param or first message
            let user: User
            if let token = req.query[String.self, at: "token"] {
                let payload = try await req.jwt.verify(token, as: AccessTokenPayload.self)
                guard let u = try await User.find(payload.userID, on: req.db) else {
                    try await ws.close(code: .policyViolation)
                    return
                }
                user = u
            } else {
                let token: String = try await withCheckedThrowingContinuation { continuation in
                    ws.onText { _, text in
                        continuation.resume(returning: text)
                    }
                }
                let payload = try await req.jwt.verify(token, as: AccessTokenPayload.self)
                guard let u = try await User.find(payload.userID, on: req.db) else {
                    try await ws.close(code: .policyViolation)
                    return
                }
                user = u
            }

            // Validate VM
            guard let vmIDString = req.parameters.get("vmID"),
                  let vmID = UUID(uuidString: vmIDString) else {
                try await ws.close(code: .policyViolation)
                return
            }

            guard let vm = try await CloudVM.find(vmID, on: req.db),
                  vm.$user.id == user.id else {
                try await ws.close(code: .policyViolation)
                return
            }

            // VM must be running
            guard vm.state == .running else {
                ws.send("{\"error\":\"VM is not running.\"}")
                try await ws.close(code: .normalClosure)
                return
            }

            // Register with proxy service
            await displayProxy.registerClient(vmID: vmID, channel: channel, ws: ws, app: req.application)

            req.logger.info("Display proxy: \(channel.rawValue) connected for VM \(vmID)")

            // Set up idle timeout (5 minutes)
            let timeoutSeconds: UInt64 = 300
            let lastActivity = ManagedAtomic<UInt64>(UInt64(Date().timeIntervalSince1970))

            // Handle incoming text frames
            ws.onText { _, text in
                lastActivity.store(UInt64(Date().timeIntervalSince1970), ordering: .relaxed)
                Task {
                    await displayProxy.relayTextFromClient(vmID: vmID, channel: channel, text: text, app: req.application)
                }
            }

            // Handle incoming binary frames
            ws.onBinary { _, data in
                lastActivity.store(UInt64(Date().timeIntervalSince1970), ordering: .relaxed)
                Task {
                    await displayProxy.relayBinaryFromClient(vmID: vmID, channel: channel, data: data, app: req.application)
                }
            }

            // Timeout check loop
            Task {
                while !ws.isClosed {
                    try await Task.sleep(for: .seconds(30))
                    let last = lastActivity.load(ordering: .relaxed)
                    let now = UInt64(Date().timeIntervalSince1970)
                    if now - last > timeoutSeconds {
                        req.logger.info("Display proxy: \(channel.rawValue) timed out for VM \(vmID)")
                        try await ws.close(code: .normalClosure)
                        break
                    }
                }
            }

            // Clean up on close
            ws.onClose.whenComplete { _ in
                Task {
                    await displayProxy.removeClient(vmID: vmID, channel: channel)
                    req.logger.info("Display proxy: \(channel.rawValue) disconnected for VM \(vmID)")
                }
            }

        } catch {
            req.logger.error("Display proxy error: \(error)")
            try? await ws.close(code: .unexpectedServerError)
        }
    }
}

// MARK: - Atomic helper (simple lock-free counter for timeout tracking)

import Foundation

/// Minimal atomic wrapper for UInt64 using os_unfair_lock.
final class ManagedAtomic<Value>: @unchecked Sendable {
    private var _value: Value
    private var lock = NSLock()

    init(_ value: Value) {
        self._value = value
    }

    func load(ordering: MemoryOrdering = .relaxed) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func store(_ value: Value, ordering: MemoryOrdering = .relaxed) {
        lock.lock()
        defer { lock.unlock() }
        _value = value
    }
}

enum MemoryOrdering {
    case relaxed
}
