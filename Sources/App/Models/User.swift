import Fluent
import Vapor

/// Tier-based access levels for users.
enum UserTier: String, Codable, CaseIterable {
    case free
    case pro
    case enterprise

    /// Maximum number of cloud VMs allowed for this tier.
    var vmLimit: Int {
        switch self {
        case .free: return 1
        case .pro: return 5
        case .enterprise: return 20
        }
    }
}

/// Registered user, linked to a Sign in with Apple identity.
final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "apple_user_id")
    var appleUserID: String

    @OptionalField(key: "email")
    var email: String?

    @Field(key: "display_name")
    var displayName: String

    @Enum(key: "tier")
    var tier: UserTier

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Children(for: \.$user)
    var vms: [CloudVM]

    @Children(for: \.$user)
    var usageRecords: [UsageRecord]

    init() {}

    init(
        id: UUID? = nil,
        appleUserID: String,
        email: String? = nil,
        displayName: String,
        tier: UserTier = .free
    ) {
        self.id = id
        self.appleUserID = appleUserID
        self.email = email
        self.displayName = displayName
        self.tier = tier
    }
}
