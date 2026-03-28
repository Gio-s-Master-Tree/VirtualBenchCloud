import Vapor
import Fluent

/// Exposes provision status and a WebSocket stream for real-time progress updates.
struct ProvisionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let provision = routes.grouped("vms", ":vmID", "provision")
        provision.get(use: getStatus)
        provision.webSocket("stream", onUpgrade: streamProgress)
    }

    // MARK: - GET /vms/:vmID/provision

    @Sendable
    func getStatus(req: Request) async throws -> ProvisionJobDTO {
        let user = try req.requireAuthUser()
        let vm = try await requireOwnedVM(vmID: req.parameters.get("vmID"), userID: user.id!, on: req.db)

        guard let job = try await ProvisionJob.query(on: req.db)
            .filter(\.$vm.$id == vm.id!)
            .sort(\.$startedAt, .descending)
            .first()
        else {
            throw Abort(.notFound, reason: "No provision job found for this VM.")
        }

        return ProvisionJobDTO(from: job)
    }

    // MARK: - WS /vms/:vmID/provision/stream

    /// WebSocket endpoint that pushes provision progress updates until the job completes or fails.
    @Sendable
    func streamProgress(req: Request, ws: WebSocket) async {
        do {
            // Authenticate via query parameter or first text message
            let user: User
            if let token = req.query[String.self, at: "token"] {
                let payload = try await req.jwt.verify(token, as: AccessTokenPayload.self)
                guard let u = try await User.find(payload.userID, on: req.db) else {
                    try await ws.close(code: .policyViolation)
                    return
                }
                user = u
            } else {
                // Wait for the first message as an auth token
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

            guard let vmIDString = req.parameters.get("vmID"),
                  let vmID = UUID(uuidString: vmIDString) else {
                try await ws.close(code: .policyViolation)
                return
            }

            // Verify ownership
            guard let vm = try await CloudVM.find(vmID, on: req.db),
                  vm.$user.id == user.id else {
                try await ws.close(code: .policyViolation)
                return
            }

            // Poll and push updates
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var lastProgress = -1

            while !ws.isClosed {
                guard let job = try await ProvisionJob.query(on: req.db)
                    .filter(\.$vm.$id == vmID)
                    .sort(\.$startedAt, .descending)
                    .first()
                else {
                    break
                }

                if job.progress != lastProgress {
                    lastProgress = job.progress
                    let update = ProvisionUpdate(
                        status: job.status,
                        progress: job.progress,
                        message: job.message ?? ""
                    )
                    let data = try encoder.encode(update)
                    ws.send(String(data: data, encoding: .utf8) ?? "{}")
                }

                // Stop streaming once terminal
                if job.status == .ready || job.status == .failed {
                    try await ws.close(code: .normalClosure)
                    break
                }

                try await Task.sleep(for: .milliseconds(500))
            }

        } catch {
            req.logger.error("Provision stream error: \(error)")
            try? await ws.close(code: .unexpectedServerError)
        }
    }

    // MARK: - Helpers

    private func requireOwnedVM(vmID: String?, userID: UUID, on db: any Database) async throws -> CloudVM {
        guard let vmIDString = vmID, let vmID = UUID(uuidString: vmIDString) else {
            throw Abort(.badRequest, reason: "Invalid VM ID.")
        }
        guard let vm = try await CloudVM.find(vmID, on: db) else {
            throw Abort(.notFound, reason: "VM not found.")
        }
        guard vm.$user.id == userID else {
            throw Abort(.forbidden, reason: "You do not own this VM.")
        }
        return vm
    }
}
