import Fluent

struct CreateUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let tierEnum = try await database.enum("user_tier")
            .case("free")
            .case("pro")
            .case("enterprise")
            .create()

        try await database.schema("users")
            .id()
            .field("apple_user_id", .string, .required)
            .field("email", .string)
            .field("display_name", .string, .required)
            .field("tier", tierEnum, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "apple_user_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users").delete()
        try await database.enum("user_tier").delete()
    }
}
