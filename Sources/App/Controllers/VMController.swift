import Vapor
import Fluent

/// Full CRUD for cloud VMs with ownership validation and tier-based limits.
struct VMController: RouteCollection {
    let orchestrator: OrchestratorService
    let instanceManager: InstanceManager

    func boot(routes: any RoutesBuilder) throws {
        let vms = routes.grouped("vms")
        vms.get(use: index)
        vms.post(use: create)
        vms.get(":vmID", use: show)
        vms.delete(":vmID", use: delete)
        vms.post(":vmID", "start", use: start)
        vms.post(":vmID", "stop", use: stop)
        vms.post(":vmID", "pause", use: pause)

        // Also expose regions and instance types (public info, but under auth for consistency)
        let info = routes
        info.get("regions", use: listRegions)
        info.get("instance-types", use: listInstanceTypes)
    }

    // MARK: - List VMs

    @Sendable
    func index(req: Request) async throws -> [CloudVMDTO] {
        let user = try req.requireAuthUser()
        let vms = try await CloudVM.query(on: req.db)
            .filter(\.$user.$id == user.id!)
            .filter(\.$state != .terminated)
            .sort(\.$createdAt, .descending)
            .all()
        return vms.map { CloudVMDTO(from: $0) }
    }

    // MARK: - Create VM

    @Sendable
    func create(req: Request) async throws -> CloudVMDTO {
        let user = try req.requireAuthUser()
        try CreateVMRequest.validate(content: req)
        let body = try req.content.decode(CreateVMRequest.self)

        // Enforce tier VM limits
        let existingCount = try await CloudVM.query(on: req.db)
            .filter(\.$user.$id == user.id!)
            .filter(\.$state != .terminated)
            .count()

        guard existingCount < user.tier.vmLimit else {
            throw Abort(.forbidden, reason: "VM limit reached for \(user.tier.rawValue) tier (\(user.tier.vmLimit) max). Upgrade to create more.")
        }

        // Resolve instance type
        guard let spec = CloudInstanceType.find(body.instanceType) else {
            throw Abort(.badRequest, reason: "Unknown instance type: \(body.instanceType)")
        }

        // Resolve region
        guard let region = CloudRegion.find(body.region), region.available else {
            throw Abort(.badRequest, reason: "Region unavailable: \(body.region)")
        }

        // Create VM record
        let vm = CloudVM(
            userID: user.id!,
            name: body.name,
            guestOS: body.guestOS,
            state: .provisioning,
            instanceType: body.instanceType,
            region: body.region,
            cpuCount: spec.cpuCount,
            memoryMB: spec.memoryMB,
            diskSizeMB: spec.diskSizeMB,
            displayWidth: body.displayWidth ?? 1920,
            displayHeight: body.displayHeight ?? 1080
        )
        try await vm.save(on: req.db)

        // Create provision job
        let job = ProvisionJob(vmID: vm.id!, message: "Queued for provisioning")
        try await job.save(on: req.db)

        // Kick off simulated provisioning in background
        let vmID = vm.id!
        let regionID = body.region
        let cpuCount = spec.cpuCount
        let memoryMB = spec.memoryMB
        let diskSizeMB = spec.diskSizeMB
        let userID = user.id!
        let instanceType = body.instanceType

        req.application.logger.info("Provisioning VM \(vmID) in \(regionID)")

        Task {
            await simulateProvisioning(
                vmID: vmID,
                jobID: job.id!,
                regionID: regionID,
                cpuCount: cpuCount,
                memoryMB: memoryMB,
                diskSizeMB: diskSizeMB,
                userID: userID,
                instanceType: instanceType,
                app: req.application
            )
        }

        return CloudVMDTO(from: vm)
    }

    // MARK: - Show VM

    @Sendable
    func show(req: Request) async throws -> CloudVMDTO {
        let vm = try await requireOwnedVM(req: req)
        return CloudVMDTO(from: vm)
    }

    // MARK: - Delete (Terminate) VM

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let user = try req.requireAuthUser()
        let vm = try await requireOwnedVM(req: req)

        // Stop billing
        try await BillingService.stopTracking(vmID: vm.id!, on: req.db)

        // Deallocate host resources
        await orchestrator.deallocate(vmID: vm.id!, region: vm.region, cpuCount: vm.cpuCount, memoryMB: vm.memoryMB)
        await instanceManager.terminateVM(vmID: vm.id!)

        vm.state = .terminated
        vm.terminatedAt = Date()
        try await vm.save(on: req.db)

        req.logger.info("VM \(vm.id!) terminated by user \(user.id!)")
        return .noContent
    }

    // MARK: - Start VM

    @Sendable
    func start(req: Request) async throws -> CloudVMDTO {
        let user = try req.requireAuthUser()
        let vm = try await requireOwnedVM(req: req)

        guard vm.state == .stopped || vm.state == .paused else {
            throw Abort(.conflict, reason: "VM cannot be started from state: \(vm.state.rawValue)")
        }

        if vm.state == .paused {
            let resumed = await instanceManager.resumeVM(vmID: vm.id!)
            guard resumed else {
                throw Abort(.internalServerError, reason: "Failed to resume VM on host.")
            }
        } else {
            // Re-allocate host if needed
            if vm.hostAddress == nil {
                guard let address = await orchestrator.allocateHost(vmID: vm.id!, region: vm.region, cpuCount: vm.cpuCount, memoryMB: vm.memoryMB) else {
                    throw Abort(.serviceUnavailable, reason: "No available hosts in region \(vm.region).")
                }
                vm.hostAddress = address
            }

            let started = await instanceManager.startVM(vmID: vm.id!, hostAddress: vm.hostAddress!, memoryTotalMB: vm.memoryMB, diskTotalMB: vm.diskSizeMB)
            guard started else {
                throw Abort(.internalServerError, reason: "Failed to start VM on host.")
            }
        }

        vm.state = .running
        vm.lastStartedAt = Date()
        try await vm.save(on: req.db)

        // Start billing
        _ = try await BillingService.startTracking(
            userID: user.id!,
            vmID: vm.id!,
            instanceType: vm.instanceType,
            on: req.db
        )

        return CloudVMDTO(from: vm)
    }

    // MARK: - Stop VM

    @Sendable
    func stop(req: Request) async throws -> CloudVMDTO {
        let vm = try await requireOwnedVM(req: req)

        guard vm.state == .running || vm.state == .paused else {
            throw Abort(.conflict, reason: "VM cannot be stopped from state: \(vm.state.rawValue)")
        }

        let stopped = await instanceManager.stopVM(vmID: vm.id!)
        guard stopped else {
            throw Abort(.internalServerError, reason: "Failed to stop VM on host.")
        }

        vm.state = .stopped
        try await vm.save(on: req.db)

        // Stop billing
        try await BillingService.stopTracking(vmID: vm.id!, on: req.db)

        return CloudVMDTO(from: vm)
    }

    // MARK: - Pause VM

    @Sendable
    func pause(req: Request) async throws -> CloudVMDTO {
        let vm = try await requireOwnedVM(req: req)

        guard vm.state == .running else {
            throw Abort(.conflict, reason: "VM can only be paused from running state.")
        }

        let paused = await instanceManager.pauseVM(vmID: vm.id!)
        guard paused else {
            throw Abort(.internalServerError, reason: "Failed to pause VM on host.")
        }

        vm.state = .paused
        try await vm.save(on: req.db)

        return CloudVMDTO(from: vm)
    }

    // MARK: - Regions & Instance Types

    @Sendable
    func listRegions(req: Request) async throws -> [RegionDTO] {
        CloudRegion.all.map { RegionDTO(id: $0.id, name: $0.name, available: $0.available) }
    }

    @Sendable
    func listInstanceTypes(req: Request) async throws -> [InstanceTypeDTO] {
        CloudInstanceType.all.map {
            InstanceTypeDTO(id: $0.id, cpuCount: $0.cpuCount, memoryMB: $0.memoryMB, diskSizeMB: $0.diskSizeMB, centsPerHour: $0.centsPerHour)
        }
    }

    // MARK: - Helpers

    /// Fetches a VM by ID from the route parameter and validates ownership.
    private func requireOwnedVM(req: Request) async throws -> CloudVM {
        let user = try req.requireAuthUser()

        guard let vmIDString = req.parameters.get("vmID"),
              let vmID = UUID(uuidString: vmIDString) else {
            throw Abort(.badRequest, reason: "Invalid VM ID.")
        }

        guard let vm = try await CloudVM.find(vmID, on: req.db) else {
            throw Abort(.notFound, reason: "VM not found.")
        }

        guard vm.$user.id == user.id else {
            throw Abort(.forbidden, reason: "You do not own this VM.")
        }

        return vm
    }

    /// Simulates the provisioning workflow in background.
    private func simulateProvisioning(
        vmID: UUID,
        jobID: UUID,
        regionID: String,
        cpuCount: Int,
        memoryMB: Int,
        diskSizeMB: Int,
        userID: UUID,
        instanceType: String,
        app: Application
    ) async {
        let db = app.db

        do {
            guard let job = try await ProvisionJob.find(jobID, on: db) else { return }

            // Phase 1: Allocating host
            job.status = .allocatingHost
            job.progress = 10
            job.message = "Allocating Apple Silicon host..."
            job.startedAt = Date()
            try await job.save(on: db)
            try await Task.sleep(for: .seconds(1))

            guard let hostAddress = await orchestrator.allocateHost(vmID: vmID, region: regionID, cpuCount: cpuCount, memoryMB: memoryMB) else {
                job.status = .failed
                job.message = "No available hosts in region."
                try await job.save(on: db)

                if let vm = try await CloudVM.find(vmID, on: db) {
                    vm.state = .error
                    try await vm.save(on: db)
                }
                return
            }

            job.progress = 30
            job.message = "Host allocated: \(hostAddress)"
            try await job.save(on: db)

            // Phase 2: Installing OS
            job.status = .installingOS
            job.progress = 50
            job.message = "Installing guest operating system..."
            try await job.save(on: db)
            try await Task.sleep(for: .seconds(2))

            // Phase 3: Configuring
            job.status = .configuring
            job.progress = 80
            job.message = "Configuring VM environment..."
            try await job.save(on: db)
            try await Task.sleep(for: .seconds(1))

            // Phase 4: Start the VM
            let started = await instanceManager.startVM(vmID: vmID, hostAddress: hostAddress, memoryTotalMB: memoryMB, diskTotalMB: diskSizeMB)

            if started, let vm = try await CloudVM.find(vmID, on: db) {
                vm.state = .running
                vm.hostAddress = hostAddress
                vm.lastStartedAt = Date()
                try await vm.save(on: db)

                // Start billing
                _ = try await BillingService.startTracking(
                    userID: userID,
                    vmID: vmID,
                    instanceType: instanceType,
                    on: db
                )
            }

            // Phase 5: Ready
            job.status = .ready
            job.progress = 100
            job.message = "VM is running."
            job.completedAt = Date()
            try await job.save(on: db)

            app.logger.info("Provisioning complete for VM \(vmID)")

        } catch {
            app.logger.error("Provisioning failed for VM \(vmID): \(error)")
            // Best-effort: mark job failed
            if let job = try? await ProvisionJob.find(jobID, on: db) {
                job.status = .failed
                job.message = "Internal error: \(error.localizedDescription)"
                try? await job.save(on: db)
            }
        }
    }
}
