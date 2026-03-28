import Fluent

struct CreateCloudVM: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let guestOSEnum = try await database.enum("guest_os")
            .case("linux")
            .case("macOS")
            .case("windows")
            .create()

        let vmStateEnum = try await database.enum("vm_state")
            .case("provisioning")
            .case("stopped")
            .case("starting")
            .case("running")
            .case("paused")
            .case("error")
            .case("terminated")
            .create()

        try await database.schema("cloud_vms")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("name", .string, .required)
            .field("guest_os", guestOSEnum, .required)
            .field("state", vmStateEnum, .required)
            .field("instance_type", .string, .required)
            .field("region", .string, .required)
            .field("host_address", .string)
            .field("cpu_count", .int, .required)
            .field("memory_mb", .int, .required)
            .field("disk_size_mb", .int, .required)
            .field("display_width", .int, .required)
            .field("display_height", .int, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .field("last_started_at", .datetime)
            .field("terminated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("cloud_vms").delete()
        try await database.enum("vm_state").delete()
        try await database.enum("guest_os").delete()
    }
}
