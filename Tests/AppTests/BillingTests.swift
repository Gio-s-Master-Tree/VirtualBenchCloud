@testable import App
import XCTVapor
import Fluent

final class BillingTests: XCTestCase {
    var app: Application!
    var accessToken: String!
    var userID: UUID!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        try await configure(app)

        // Create a test user
        var authResponse: AuthResponse!
        try await app.test(.POST, "auth/signin", beforeRequest: { req in
            try req.content.encode(SignInRequest(identityToken: "billing-test-user"))
        }, afterResponse: { res async throws in
            authResponse = try res.content.decode(AuthResponse.self)
        })
        accessToken = authResponse.accessToken
        userID = authResponse.user.id
    }

    override func tearDown() async throws {
        try await app.autoRevert()
        try await app.asyncShutdown()
    }

    private func authHeaders() -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: accessToken)
        return headers
    }

    // MARK: - Cost Calculation

    func testCostCalculation_starter() {
        // Starter: 5 cents/hour = 0.0833 cents/minute
        // 60 minutes → 5 cents
        let cost = BillingService.calculateCost(instanceType: "starter", durationMinutes: 60)
        XCTAssertEqual(cost, 5)
    }

    func testCostCalculation_pro() {
        // Pro: 10 cents/hour
        // 120 minutes → 20 cents
        let cost = BillingService.calculateCost(instanceType: "pro", durationMinutes: 120)
        XCTAssertEqual(cost, 20)
    }

    func testCostCalculation_max() {
        // Max: 20 cents/hour
        // 30 minutes → 10 cents
        let cost = BillingService.calculateCost(instanceType: "max", durationMinutes: 30)
        XCTAssertEqual(cost, 10)
    }

    func testCostCalculation_ultra() {
        // Ultra: 40 cents/hour
        // 90 minutes → 60 cents
        let cost = BillingService.calculateCost(instanceType: "ultra", durationMinutes: 90)
        XCTAssertEqual(cost, 60)
    }

    func testCostCalculation_unknownType() {
        let cost = BillingService.calculateCost(instanceType: "nonexistent", durationMinutes: 60)
        XCTAssertEqual(cost, 0)
    }

    func testCostCalculation_roundsUp() {
        // Starter: 5 cents/hour. 1 minute → ceil(5/60 * 1) = ceil(0.0833) = 1 cent
        let cost = BillingService.calculateCost(instanceType: "starter", durationMinutes: 1)
        XCTAssertEqual(cost, 1)
    }

    // MARK: - Usage Tracking

    func testStartAndStopTracking() async throws {
        // Create a VM first
        let vm = CloudVM(
            userID: userID,
            name: "Billing Test VM",
            guestOS: .linux,
            state: .running,
            instanceType: "pro",
            region: "us-west-1",
            cpuCount: 4,
            memoryMB: 16384,
            diskSizeMB: 262144
        )
        try await vm.save(on: app.db)

        // Start tracking
        let record = try await BillingService.startTracking(
            userID: userID,
            vmID: vm.id!,
            instanceType: "pro",
            on: app.db
        )

        XCTAssertNil(record.endedAt)
        XCTAssertEqual(record.durationMinutes, 0)
        XCTAssertEqual(record.costCents, 0)
        XCTAssertEqual(record.instanceType, "pro")

        // Stop tracking
        try await BillingService.stopTracking(vmID: vm.id!, on: app.db)

        // Reload record
        guard let updated = try await UsageRecord.find(record.id!, on: app.db) else {
            XCTFail("Record not found after stop tracking")
            return
        }

        XCTAssertNotNil(updated.endedAt)
        XCTAssertGreaterThanOrEqual(updated.durationMinutes, 1)
        XCTAssertGreaterThan(updated.costCents, 0)
    }

    // MARK: - Billing API Endpoints

    func testCurrentUsage_empty() async throws {
        try await app.test(.GET, "billing/usage", headers: authHeaders(), afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let summary = try res.content.decode(CurrentBillingPeriodDTO.self)
            XCTAssertEqual(summary.totalCostCents, 0)
            XCTAssertEqual(summary.totalMinutes, 0)
            XCTAssertTrue(summary.records.isEmpty)
        })
    }

    func testBillingHistory_empty() async throws {
        try await app.test(.GET, "billing/history", headers: authHeaders(), afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let history = try res.content.decode([BillingPeriodDTO].self)
            XCTAssertTrue(history.isEmpty)
        })
    }

    func testCostEstimate() async throws {
        try await app.test(.GET, "billing/estimate", headers: authHeaders(), afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let estimate = try res.content.decode(CostEstimateDTO.self)
            XCTAssertGreaterThanOrEqual(estimate.estimatedMonthlyCostCents, 0)
        })
    }

    // MARK: - Billing Unauthenticated

    func testBillingUsage_noAuth_returns401() async throws {
        try await app.test(.GET, "billing/usage", afterResponse: { res async throws in
            XCTAssertEqual(res.status, .unauthorized)
        })
    }
}
