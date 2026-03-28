import Fluent

struct CreateUsageRecord: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("usage_records")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("vm_id", .uuid, .required, .references("cloud_vms", "id", onDelete: .cascade))
            .field("instance_type", .string, .required)
            .field("started_at", .datetime, .required)
            .field("ended_at", .datetime)
            .field("duration_minutes", .int, .required)
            .field("cost_cents", .int, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("usage_records").delete()
    }
}
