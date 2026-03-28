import Vapor
import Fluent

/// Real-time and historical VM performance metrics.
struct MetricsController: RouteCollection {
    let instanceManager: InstanceManager

    func boot(routes: any RoutesBuilder) throws {
        let metrics = routes.grouped("vms", ":vmID", "metrics")
        metrics.get(use: current)
        metrics.get("history", use: history)
    }

    // MARK: - GET /vms/:vmID/metrics — Current metrics snapshot

    @Sendable
    func current(req: Request) async throws -> VMMetricsDTO {
        let user = try req.requireAuthUser()
        let vm = try await requireOwnedVM(vmID: req.parameters.get("vmID"), userID: user.id!, on: req.db)

        guard vm.state == .running || vm.state == .paused else {
            throw Abort(.conflict, reason: "Metrics are only available for running or paused VMs.")
        }

        guard let instance = await instanceManager.metrics(vmID: vm.id!) else {
            throw Abort(.serviceUnavailable, reason: "Unable to retrieve metrics from host.")
        }

        return VMMetricsDTO(
            vmID: vm.id!,
            timestamp: Date(),
            cpuUsagePercent: instance.cpuUsagePercent,
            memoryUsedMB: instance.memoryUsedMB,
            memoryTotalMB: instance.memoryTotalMB,
            diskUsedMB: instance.diskUsedMB,
            diskTotalMB: instance.diskTotalMB,
            networkInBytesPerSec: instance.networkInBytesPerSec,
            networkOutBytesPerSec: instance.networkOutBytesPerSec
        )
    }

    // MARK: - GET /vms/:vmID/metrics/history?period=1h — Historical metrics

    @Sendable
    func history(req: Request) async throws -> [VMMetricsDTO] {
        let user = try req.requireAuthUser()
        let vm = try await requireOwnedVM(vmID: req.parameters.get("vmID"), userID: user.id!, on: req.db)

        let periodString = req.query[String.self, at: "period"] ?? "1h"
        let dataPoints = dataPointCount(for: periodString)

        // Generate simulated historical data points.
        // In production this would query a time-series database (InfluxDB, TimescaleDB, etc.).
        var history: [VMMetricsDTO] = []
        let now = Date()
        let intervalSeconds = periodSeconds(for: periodString) / Double(dataPoints)

        for i in (0..<dataPoints).reversed() {
            let timestamp = now.addingTimeInterval(-Double(i) * intervalSeconds)
            history.append(VMMetricsDTO(
                vmID: vm.id!,
                timestamp: timestamp,
                cpuUsagePercent: Double.random(in: 1.0...80.0),
                memoryUsedMB: Int.random(in: 512...vm.memoryMB),
                memoryTotalMB: vm.memoryMB,
                diskUsedMB: Int.random(in: 4096...vm.diskSizeMB / 2),
                diskTotalMB: vm.diskSizeMB,
                networkInBytesPerSec: Int.random(in: 100...100_000),
                networkOutBytesPerSec: Int.random(in: 50...50_000)
            ))
        }

        return history
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

    private func periodSeconds(for period: String) -> Double {
        switch period {
        case "5m": return 5 * 60
        case "15m": return 15 * 60
        case "1h": return 60 * 60
        case "6h": return 6 * 60 * 60
        case "24h": return 24 * 60 * 60
        case "7d": return 7 * 24 * 60 * 60
        default: return 60 * 60
        }
    }

    private func dataPointCount(for period: String) -> Int {
        switch period {
        case "5m": return 30
        case "15m": return 45
        case "1h": return 60
        case "6h": return 72
        case "24h": return 96
        case "7d": return 168
        default: return 60
        }
    }
}
