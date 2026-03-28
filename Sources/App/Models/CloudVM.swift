import Fluent
import Vapor

/// Operating system running inside the VM.
enum GuestOS: String, Codable, CaseIterable {
    case linux
    case macOS
    case windows
}

/// Lifecycle state of a cloud VM.
enum VMState: String, Codable, CaseIterable {
    case provisioning
    case stopped
    case starting
    case running
    case paused
    case error
    case terminated
}

/// A cloud-hosted virtual machine instance.
final class CloudVM: Model, Content, @unchecked Sendable {
    static let schema = "cloud_vms"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "name")
    var name: String

    @Enum(key: "guest_os")
    var guestOS: GuestOS

    @Enum(key: "state")
    var state: VMState

    @Field(key: "instance_type")
    var instanceType: String

    @Field(key: "region")
    var region: String

    @OptionalField(key: "host_address")
    var hostAddress: String?

    @Field(key: "cpu_count")
    var cpuCount: Int

    @Field(key: "memory_mb")
    var memoryMB: Int

    @Field(key: "disk_size_mb")
    var diskSizeMB: Int

    @Field(key: "display_width")
    var displayWidth: Int

    @Field(key: "display_height")
    var displayHeight: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @OptionalField(key: "last_started_at")
    var lastStartedAt: Date?

    @OptionalField(key: "terminated_at")
    var terminatedAt: Date?

    @Children(for: \.$vm)
    var provisionJobs: [ProvisionJob]

    @Children(for: \.$vm)
    var usageRecords: [UsageRecord]

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        name: String,
        guestOS: GuestOS,
        state: VMState = .provisioning,
        instanceType: String,
        region: String,
        hostAddress: String? = nil,
        cpuCount: Int,
        memoryMB: Int,
        diskSizeMB: Int,
        displayWidth: Int = 1920,
        displayHeight: Int = 1080,
        lastStartedAt: Date? = nil,
        terminatedAt: Date? = nil
    ) {
        self.id = id
        self.$user.id = userID
        self.name = name
        self.guestOS = guestOS
        self.state = state
        self.instanceType = instanceType
        self.region = region
        self.hostAddress = hostAddress
        self.cpuCount = cpuCount
        self.memoryMB = memoryMB
        self.diskSizeMB = diskSizeMB
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.lastStartedAt = lastStartedAt
        self.terminatedAt = terminatedAt
    }
}
