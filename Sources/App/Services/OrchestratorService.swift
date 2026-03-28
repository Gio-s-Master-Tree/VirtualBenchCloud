import Vapor
import Foundation

// MARK: - Region & Instance Type Configuration

/// Hardcoded cloud regions.
struct CloudRegion: Sendable {
    let id: String
    let name: String
    let available: Bool

    static let all: [CloudRegion] = [
        CloudRegion(id: "us-west-1", name: "US West (California)", available: true),
        CloudRegion(id: "us-east-1", name: "US East (Virginia)", available: true),
        CloudRegion(id: "eu-west-1", name: "Europe (Ireland)", available: true),
        CloudRegion(id: "ap-southeast-1", name: "Asia Pacific (Singapore)", available: true),
    ]

    static func find(_ id: String) -> CloudRegion? {
        all.first { $0.id == id }
    }
}

/// Hardcoded instance types with pricing.
struct CloudInstanceType: Sendable {
    let id: String
    let cpuCount: Int
    let memoryMB: Int
    let diskSizeMB: Int
    let centsPerHour: Int

    static let all: [CloudInstanceType] = [
        CloudInstanceType(id: "starter", cpuCount: 2, memoryMB: 8192, diskSizeMB: 131_072, centsPerHour: 5),
        CloudInstanceType(id: "pro", cpuCount: 4, memoryMB: 16_384, diskSizeMB: 262_144, centsPerHour: 10),
        CloudInstanceType(id: "max", cpuCount: 8, memoryMB: 32_768, diskSizeMB: 524_288, centsPerHour: 20),
        CloudInstanceType(id: "ultra", cpuCount: 16, memoryMB: 65_536, diskSizeMB: 1_048_576, centsPerHour: 40),
    ]

    static func find(_ id: String) -> CloudInstanceType? {
        all.first { $0.id == id }
    }
}

// MARK: - Simulated Host

/// Represents a single Apple Silicon cloud host in the simulated pool.
struct SimulatedHost: Sendable {
    let id: UUID
    let region: String
    let address: String
    let totalCPU: Int
    let totalMemoryMB: Int
    var allocatedCPU: Int
    var allocatedMemoryMB: Int
    var vmIDs: [UUID]

    var availableCPU: Int { totalCPU - allocatedCPU }
    var availableMemoryMB: Int { totalMemoryMB - allocatedMemoryMB }

    func canFit(cpuCount: Int, memoryMB: Int) -> Bool {
        availableCPU >= cpuCount && availableMemoryMB >= memoryMB
    }
}

// MARK: - OrchestratorService

/// Manages a simulated pool of Apple Silicon cloud hosts.
/// In production, this would interface with real infrastructure (MacStadium, AWS Mac instances, etc.).
actor OrchestratorService {
    /// Pool of simulated hosts per region.
    private var hosts: [String: [SimulatedHost]]

    /// Mapping from VM ID to host ID for quick lookup.
    private var vmToHost: [UUID: UUID] = [:]

    init() {
        // Seed each region with 3 simulated hosts (M2 Ultra-class: 24 CPU, 192 GB RAM).
        var pool: [String: [SimulatedHost]] = [:]
        for region in CloudRegion.all {
            var regionHosts: [SimulatedHost] = []
            for i in 0..<3 {
                let host = SimulatedHost(
                    id: UUID(),
                    region: region.id,
                    address: "10.\(region.id.hashValue & 0xFF).\(i).1",
                    totalCPU: 24,
                    totalMemoryMB: 196_608, // 192 GB
                    allocatedCPU: 0,
                    allocatedMemoryMB: 0,
                    vmIDs: []
                )
                regionHosts.append(host)
            }
            pool[region.id] = regionHosts
        }
        self.hosts = pool
    }

    /// Allocate a host for a VM. Returns the host address or nil if no capacity.
    func allocateHost(vmID: UUID, region: String, cpuCount: Int, memoryMB: Int) -> String? {
        guard var regionHosts = hosts[region] else { return nil }

        for i in regionHosts.indices {
            if regionHosts[i].canFit(cpuCount: cpuCount, memoryMB: memoryMB) {
                regionHosts[i].allocatedCPU += cpuCount
                regionHosts[i].allocatedMemoryMB += memoryMB
                regionHosts[i].vmIDs.append(vmID)

                let address = regionHosts[i].address
                let hostID = regionHosts[i].id

                hosts[region] = regionHosts
                vmToHost[vmID] = hostID
                return address
            }
        }
        return nil
    }

    /// Release a host allocation for a VM.
    func deallocate(vmID: UUID, region: String, cpuCount: Int, memoryMB: Int) {
        guard var regionHosts = hosts[region] else { return }

        if let hostID = vmToHost[vmID] {
            for i in regionHosts.indices where regionHosts[i].id == hostID {
                regionHosts[i].allocatedCPU = max(0, regionHosts[i].allocatedCPU - cpuCount)
                regionHosts[i].allocatedMemoryMB = max(0, regionHosts[i].allocatedMemoryMB - memoryMB)
                regionHosts[i].vmIDs.removeAll { $0 == vmID }
                break
            }
            hosts[region] = regionHosts
            vmToHost.removeValue(forKey: vmID)
        }
    }

    /// Health check: returns the number of healthy hosts per region.
    func healthCheck() -> [String: Int] {
        var result: [String: Int] = [:]
        for (region, regionHosts) in hosts {
            result[region] = regionHosts.count
        }
        return result
    }

    /// Returns capacity info for a region.
    func regionCapacity(region: String) -> (totalCPU: Int, availableCPU: Int, totalMemoryMB: Int, availableMemoryMB: Int)? {
        guard let regionHosts = hosts[region] else { return nil }
        let totalCPU = regionHosts.reduce(0) { $0 + $1.totalCPU }
        let availableCPU = regionHosts.reduce(0) { $0 + $1.availableCPU }
        let totalMem = regionHosts.reduce(0) { $0 + $1.totalMemoryMB }
        let availableMem = regionHosts.reduce(0) { $0 + $1.availableMemoryMB }
        return (totalCPU, availableCPU, totalMem, availableMem)
    }
}
