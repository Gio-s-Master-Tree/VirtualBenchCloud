@testable import App
import XCTVapor
import Fluent

final class VMControllerTests: XCTestCase {
    var app: Application!
    var accessToken: String!
    var userID: UUID!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        try await configure(app)

        // Create a test user and get a token
        var authResponse: AuthResponse!
        try await app.test(.POST, "auth/signin", beforeRequest: { req in
            try req.content.encode(SignInRequest(identityToken: "vm-test-user"))
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

    // MARK: - Helpers

    private func authHeaders() -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: accessToken)
        return headers
    }

    // MARK: - List VMs

    func testListVMs_empty() async throws {
        try await app.test(.GET, "vms", headers: authHeaders(), afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let vms = try res.content.decode([CloudVMDTO].self)
            XCTAssertTrue(vms.isEmpty)
        })
    }

    // MARK: - Create VM

    func testCreateVM_success() async throws {
        try await app.test(.POST, "vms", headers: authHeaders(), beforeRequest: { req in
            try req.content.encode(CreateVMRequest(
                name: "Test Linux VM",
                guestOS: .linux,
                instanceType: "starter",
                region: "us-west-1",
                displayWidth: nil,
                displayHeight: nil
            ))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let vm = try res.content.decode(CloudVMDTO.self)
            XCTAssertEqual(vm.name, "Test Linux VM")
            XCTAssertEqual(vm.guestOS, .linux)
            XCTAssertEqual(vm.state, .provisioning)
            XCTAssertEqual(vm.instanceType, "starter")
            XCTAssertEqual(vm.region, "us-west-1")
            XCTAssertEqual(vm.cpuCount, 2)
            XCTAssertEqual(vm.memoryMB, 8192)
        })
    }

    func testCreateVM_invalidInstanceType() async throws {
        try await app.test(.POST, "vms", headers: authHeaders(), beforeRequest: { req in
            try req.content.encode(CreateVMRequest(
                name: "Bad VM",
                guestOS: .linux,
                instanceType: "nonexistent",
                region: "us-west-1",
                displayWidth: nil,
                displayHeight: nil
            ))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        })
    }

    func testCreateVM_invalidRegion() async throws {
        try await app.test(.POST, "vms", headers: authHeaders(), beforeRequest: { req in
            try req.content.encode(CreateVMRequest(
                name: "Bad VM",
                guestOS: .linux,
                instanceType: "starter",
                region: "mars-1",
                displayWidth: nil,
                displayHeight: nil
            ))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        })
    }

    // MARK: - Tier Limits

    func testCreateVM_freeTierLimit() async throws {
        // Free tier: max 1 VM. Create the first one.
        try await app.test(.POST, "vms", headers: authHeaders(), beforeRequest: { req in
            try req.content.encode(CreateVMRequest(
                name: "VM 1",
                guestOS: .linux,
                instanceType: "starter",
                region: "us-west-1",
                displayWidth: nil,
                displayHeight: nil
            ))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
        })

        // Second VM should be rejected
        try await app.test(.POST, "vms", headers: authHeaders(), beforeRequest: { req in
            try req.content.encode(CreateVMRequest(
                name: "VM 2",
                guestOS: .linux,
                instanceType: "starter",
                region: "us-west-1",
                displayWidth: nil,
                displayHeight: nil
            ))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .forbidden)
        })
    }

    // MARK: - Show VM

    func testShowVM_notFound() async throws {
        let fakeID = UUID()
        try await app.test(.GET, "vms/\(fakeID)", headers: authHeaders(), afterResponse: { res async throws in
            XCTAssertEqual(res.status, .notFound)
        })
    }

    // MARK: - Ownership Validation

    func testDeleteVM_notOwned_returns403() async throws {
        // Create a VM as the first user
        var vmID: UUID!
        try await app.test(.POST, "vms", headers: authHeaders(), beforeRequest: { req in
            try req.content.encode(CreateVMRequest(
                name: "User 1 VM",
                guestOS: .linux,
                instanceType: "starter",
                region: "us-west-1",
                displayWidth: nil,
                displayHeight: nil
            ))
        }, afterResponse: { res async throws in
            let vm = try res.content.decode(CloudVMDTO.self)
            vmID = vm.id
        })

        // Sign in as a different user
        var otherToken: String!
        try await app.test(.POST, "auth/signin", beforeRequest: { req in
            try req.content.encode(SignInRequest(identityToken: "other-user"))
        }, afterResponse: { res async throws in
            let auth = try res.content.decode(AuthResponse.self)
            otherToken = auth.accessToken
        })

        // Try to delete the first user's VM
        var otherHeaders = HTTPHeaders()
        otherHeaders.bearerAuthorization = BearerAuthorization(token: otherToken)

        try await app.test(.DELETE, "vms/\(vmID!)", headers: otherHeaders, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .forbidden)
        })
    }

    // MARK: - Regions & Instance Types

    func testListRegions() async throws {
        try await app.test(.GET, "regions", headers: authHeaders(), afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let regions = try res.content.decode([RegionDTO].self)
            XCTAssertEqual(regions.count, 4)
            XCTAssertTrue(regions.contains { $0.id == "us-west-1" })
        })
    }

    func testListInstanceTypes() async throws {
        try await app.test(.GET, "instance-types", headers: authHeaders(), afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let types = try res.content.decode([InstanceTypeDTO].self)
            XCTAssertEqual(types.count, 4)
            XCTAssertTrue(types.contains { $0.id == "starter" && $0.centsPerHour == 5 })
            XCTAssertTrue(types.contains { $0.id == "ultra" && $0.centsPerHour == 40 })
        })
    }
}
