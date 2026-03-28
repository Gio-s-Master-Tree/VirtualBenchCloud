import Fluent

struct CreateProvisionJob: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let provisionStatusEnum = try await database.enum("provision_status")
            .case("queued")
            .case("allocating_host")
            .case("installing_os")
            .case("configuring")
            .case("ready")
            .case("failed")
            .create()

        try await database.schema("provision_jobs")
            .id()
            .field("vm_id", .uuid, .required, .references("cloud_vms", "id", onDelete: .cascade))
            .field("status", provisionStatusEnum, .required)
            .field("progress", .int, .required)
            .field("message", .string)
            .field("started_at", .datetime)
            .field("completed_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("provision_jobs").delete()
        try await database.enum("provision_status").delete()
    }
}
