import Vapor

// MARK: - Auth DTOs

/// Sign in with Apple identity token payload.
struct SignInRequest: Content {
    let identityToken: String
}

/// Tokens returned after successful authentication.
struct AuthResponse: Content {
    let accessToken: String
    let refreshToken: String
    let user: UserDTO
}

/// Refresh an expired access token.
struct RefreshTokenRequest: Content {
    let refreshToken: String
}

/// New token pair after refresh.
struct TokenResponse: Content {
    let accessToken: String
    let refreshToken: String
}

// MARK: - User DTO

/// Public-facing user representation.
struct UserDTO: Content {
    let id: UUID
    let email: String?
    let displayName: String
    let tier: UserTier

    init(from user: User) {
        self.id = user.id!
        self.email = user.email
        self.displayName = user.displayName
        self.tier = user.tier
    }
}

// MARK: - Cloud VM DTOs

/// Request to create a new cloud VM.
struct CreateVMRequest: Content, Validatable {
    let name: String
    let guestOS: GuestOS
    let instanceType: String
    let region: String
    let displayWidth: Int?
    let displayHeight: Int?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(1...64))
        validations.add("instanceType", as: String.self, is: .in("starter", "pro", "max", "ultra"))
        validations.add("region", as: String.self, is: .in("us-west-1", "us-east-1", "eu-west-1", "ap-southeast-1"))
    }
}

/// Public-facing VM representation.
struct CloudVMDTO: Content {
    let id: UUID
    let userID: UUID
    let name: String
    let guestOS: GuestOS
    let state: VMState
    let instanceType: String
    let region: String
    let cpuCount: Int
    let memoryMB: Int
    let diskSizeMB: Int
    let displayWidth: Int
    let displayHeight: Int
    let createdAt: Date?
    let updatedAt: Date?
    let lastStartedAt: Date?
    let terminatedAt: Date?

    init(from vm: CloudVM) {
        self.id = vm.id!
        self.userID = vm.$user.id
        self.name = vm.name
        self.guestOS = vm.guestOS
        self.state = vm.state
        self.instanceType = vm.instanceType
        self.region = vm.region
        self.cpuCount = vm.cpuCount
        self.memoryMB = vm.memoryMB
        self.diskSizeMB = vm.diskSizeMB
        self.displayWidth = vm.displayWidth
        self.displayHeight = vm.displayHeight
        self.createdAt = vm.createdAt
        self.updatedAt = vm.updatedAt
        self.lastStartedAt = vm.lastStartedAt
        self.terminatedAt = vm.terminatedAt
    }
}

// MARK: - Provision DTOs

/// Public-facing provision job representation.
struct ProvisionJobDTO: Content {
    let id: UUID
    let vmID: UUID
    let status: ProvisionStatus
    let progress: Int
    let message: String?
    let startedAt: Date?
    let completedAt: Date?

    init(from job: ProvisionJob) {
        self.id = job.id!
        self.vmID = job.$vm.id
        self.status = job.status
        self.progress = job.progress
        self.message = job.message
        self.startedAt = job.startedAt
        self.completedAt = job.completedAt
    }
}

/// WebSocket message for provision progress updates.
struct ProvisionUpdate: Codable {
    let status: ProvisionStatus
    let progress: Int
    let message: String
}

// MARK: - Metrics DTOs

/// Real-time performance metrics for a VM.
struct VMMetricsDTO: Content {
    let vmID: UUID
    let timestamp: Date
    let cpuUsagePercent: Double
    let memoryUsedMB: Int
    let memoryTotalMB: Int
    let diskUsedMB: Int
    let diskTotalMB: Int
    let networkInBytesPerSec: Int
    let networkOutBytesPerSec: Int
}

// MARK: - Billing DTOs

/// Summary of the current billing period.
struct CurrentBillingPeriodDTO: Content {
    let periodStart: Date
    let periodEnd: Date
    let totalCostCents: Int
    let totalMinutes: Int
    let records: [UsageRecordDTO]
}

/// A single billing period in history.
struct BillingPeriodDTO: Content {
    let periodStart: Date
    let periodEnd: Date
    let totalCostCents: Int
    let totalMinutes: Int
}

/// Public-facing usage record.
struct UsageRecordDTO: Content {
    let id: UUID
    let vmID: UUID
    let instanceType: String
    let startedAt: Date
    let endedAt: Date?
    let durationMinutes: Int
    let costCents: Int

    init(from record: UsageRecord) {
        self.id = record.id!
        self.vmID = record.$vm.id
        self.instanceType = record.instanceType
        self.startedAt = record.startedAt
        self.endedAt = record.endedAt
        self.durationMinutes = record.durationMinutes
        self.costCents = record.costCents
    }
}

/// Estimated monthly cost based on current usage patterns.
struct CostEstimateDTO: Content {
    let estimatedMonthlyCostCents: Int
}

// MARK: - Region & Instance Type DTOs

/// A cloud region where VMs can be provisioned.
struct RegionDTO: Content {
    let id: String
    let name: String
    let available: Bool
}

/// An available instance type with pricing.
struct InstanceTypeDTO: Content {
    let id: String
    let cpuCount: Int
    let memoryMB: Int
    let diskSizeMB: Int
    let centsPerHour: Int
}

// MARK: - JWT Payloads

import JWT

/// Payload embedded in access tokens.
struct AccessTokenPayload: JWTPayload {
    let sub: SubjectClaim
    let exp: ExpirationClaim
    let iat: IssuedAtClaim
    let userID: UUID
    let tier: UserTier

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try self.exp.verifyNotExpired()
    }
}

/// Payload embedded in refresh tokens.
struct RefreshTokenPayload: JWTPayload {
    let sub: SubjectClaim
    let exp: ExpirationClaim
    let iat: IssuedAtClaim
    let userID: UUID

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try self.exp.verifyNotExpired()
    }
}

// MARK: - Error Response

/// Standardised API error format.
struct ErrorResponse: Content {
    let error: Bool
    let reason: String
}
