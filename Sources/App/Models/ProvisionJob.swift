import Fluent
import Vapor

/// Current phase of VM provisioning.
enum ProvisionStatus: String, Codable, CaseIterable {
    case queued
    case allocatingHost = "allocating_host"
    case installingOS = "installing_os"
    case configuring
    case ready
    case failed
}

/// Tracks the provisioning lifecycle of a cloud VM.
final class ProvisionJob: Model, Content, @unchecked Sendable {
    static let schema = "provision_jobs"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "vm_id")
    var vm: CloudVM

    @Enum(key: "status")
    var status: ProvisionStatus

    @Field(key: "progress")
    var progress: Int

    @OptionalField(key: "message")
    var message: String?

    @OptionalField(key: "started_at")
    var startedAt: Date?

    @OptionalField(key: "completed_at")
    var completedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        vmID: UUID,
        status: ProvisionStatus = .queued,
        progress: Int = 0,
        message: String? = "Queued for provisioning",
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.$vm.id = vmID
        self.status = status
        self.progress = progress
        self.message = message
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}
