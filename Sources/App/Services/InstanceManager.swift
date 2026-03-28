import Vapor
import Fluent
import Foundation

/// Simulated VM instance running on a host.
struct SimulatedInstance: Sendable {
    let vmID: UUID
    let hostAddress: String
    var state: VMState
    var cpuUsagePercent: Double
    var memoryUsedMB: Int
    let memoryTotalMB: Int
    var diskUsedMB: Int
    let diskTotalMB: Int
    var networkInBytesPerSec: Int
    var networkOutBytesPerSec: Int
    var startedAt: Date?
}

/// Manages the lifecycle of VMs on simulated Apple Silicon hosts.
/// In production, this would communicate with hosts via SSH or an internal agent API.
actor InstanceManager {
    /// Active instances indexed by VM ID.
    private var instances: [UUID: SimulatedInstance] = [:]

    /// Start a VM on the specified host.
    func startVM(vmID: UUID, hostAddress: String, memoryTotalMB: Int, diskTotalMB: Int) -> Bool {
        let instance = SimulatedInstance(
            vmID: vmID,
            hostAddress: hostAddress,
            state: .running,
            cpuUsagePercent: Double.random(in: 2.0...15.0),
            memoryUsedMB: Int.random(in: 512...memoryTotalMB / 3),
            memoryTotalMB: memoryTotalMB,
            diskUsedMB: Int.random(in: 4096...diskTotalMB / 4),
            diskTotalMB: diskTotalMB,
            networkInBytesPerSec: Int.random(in: 1000...50000),
            networkOutBytesPerSec: Int.random(in: 500...20000),
            startedAt: Date()
        )
        instances[vmID] = instance
        return true
    }

    /// Stop a running VM.
    func stopVM(vmID: UUID) -> Bool {
        guard var instance = instances[vmID] else { return false }
        instance.state = .stopped
        instance.cpuUsagePercent = 0
        instance.networkInBytesPerSec = 0
        instance.networkOutBytesPerSec = 0
        instance.startedAt = nil
        instances[vmID] = instance
        return true
    }

    /// Pause a running VM.
    func pauseVM(vmID: UUID) -> Bool {
        guard var instance = instances[vmID], instance.state == .running else { return false }
        instance.state = .paused
        instance.cpuUsagePercent = 0.1
        instance.networkInBytesPerSec = 0
        instance.networkOutBytesPerSec = 0
        instances[vmID] = instance
        return true
    }

    /// Resume a paused VM.
    func resumeVM(vmID: UUID) -> Bool {
        guard var instance = instances[vmID], instance.state == .paused else { return false }
        instance.state = .running
        instance.cpuUsagePercent = Double.random(in: 2.0...15.0)
        instance.networkInBytesPerSec = Int.random(in: 1000...50000)
        instance.networkOutBytesPerSec = Int.random(in: 500...20000)
        instances[vmID] = instance
        return true
    }

    /// Terminate and remove a VM.
    func terminateVM(vmID: UUID) {
        instances.removeValue(forKey: vmID)
    }

    /// Get current metrics for a VM (with simulated jitter).
    func metrics(vmID: UUID) -> SimulatedInstance? {
        guard var instance = instances[vmID] else { return nil }

        // Add realistic jitter to make metrics look live
        if instance.state == .running {
            instance.cpuUsagePercent = max(0.1, min(100, instance.cpuUsagePercent + Double.random(in: -5.0...5.0)))
            instance.memoryUsedMB = max(256, min(instance.memoryTotalMB, instance.memoryUsedMB + Int.random(in: -100...100)))
            instance.diskUsedMB = max(1024, instance.diskUsedMB + Int.random(in: 0...5))
            instance.networkInBytesPerSec = max(0, instance.networkInBytesPerSec + Int.random(in: -5000...5000))
            instance.networkOutBytesPerSec = max(0, instance.networkOutBytesPerSec + Int.random(in: -2000...2000))
        }

        instances[vmID] = instance
        return instance
    }

    /// Check whether a VM is tracked by the instance manager.
    func isManaged(vmID: UUID) -> Bool {
        instances[vmID] != nil
    }

    /// Get the state of a managed VM.
    func instanceState(vmID: UUID) -> VMState? {
        instances[vmID]?.state
    }
}
