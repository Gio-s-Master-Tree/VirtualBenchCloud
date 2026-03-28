import Fluent
import Vapor

/// Tracks billable VM runtime for a user.
final class UsageRecord: Model, Content, @unchecked Sendable {
    static let schema = "usage_records"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Parent(key: "vm_id")
    var vm: CloudVM

    @Field(key: "instance_type")
    var instanceType: String

    @Field(key: "started_at")
    var startedAt: Date

    @OptionalField(key: "ended_at")
    var endedAt: Date?

    @Field(key: "duration_minutes")
    var durationMinutes: Int

    @Field(key: "cost_cents")
    var costCents: Int

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        vmID: UUID,
        instanceType: String,
        startedAt: Date,
        endedAt: Date? = nil,
        durationMinutes: Int = 0,
        costCents: Int = 0
    ) {
        self.id = id
        self.$user.id = userID
        self.$vm.id = vmID
        self.instanceType = instanceType
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMinutes = durationMinutes
        self.costCents = costCents
    }
}
