@testable import App
import XCTVapor
import Fluent

final class AuthTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        try await configure(app)
    }

    override func tearDown() async throws {
        try await app.autoRevert()
        try await app.asyncShutdown()
    }

    // MARK: - Sign In

    func testSignIn_createsNewUser() async throws {
        try await app.test(.POST, "auth/signin", beforeRequest: { req in
            try req.content.encode(SignInRequest(identityToken: "apple-test-user-001"))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let response = try res.content.decode(AuthResponse.self)
            XCTAssertFalse(response.accessToken.isEmpty)
            XCTAssertFalse(response.refreshToken.isEmpty)
            XCTAssertEqual(response.user.tier, .free)
        })
    }

    func testSignIn_returnsExistingUser() async throws {
        // First sign in
        try await app.test(.POST, "auth/signin", beforeRequest: { req in
            try req.content.encode(SignInRequest(identityToken: "apple-test-user-002"))
        })

        // Second sign in with same token
        try await app.test(.POST, "auth/signin", beforeRequest: { req in
            try req.content.encode(SignInRequest(identityToken: "apple-test-user-002"))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)

            // Verify only one user exists
            let users = try await User.query(on: self.app.db)
                .filter(\.$appleUserID == "apple-test-user-002")
                .all()
            XCTAssertEqual(users.count, 1)
        })
    }

    // MARK: - Refresh

    func testRefresh_validToken() async throws {
        // Sign in first
        var refreshToken = ""
        try await app.test(.POST, "auth/signin", beforeRequest: { req in
            try req.content.encode(SignInRequest(identityToken: "apple-test-user-003"))
        }, afterResponse: { res async throws in
            let response = try res.content.decode(AuthResponse.self)
            refreshToken = response.refreshToken
        })

        // Refresh
        try await app.test(.POST, "auth/refresh", beforeRequest: { req in
            try req.content.encode(RefreshTokenRequest(refreshToken: refreshToken))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let response = try res.content.decode(TokenResponse.self)
            XCTAssertFalse(response.accessToken.isEmpty)
            XCTAssertFalse(response.refreshToken.isEmpty)
        })
    }

    func testRefresh_invalidToken_returns401() async throws {
        try await app.test(.POST, "auth/refresh", beforeRequest: { req in
            try req.content.encode(RefreshTokenRequest(refreshToken: "invalid-token"))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .unauthorized)
        })
    }

    // MARK: - Protected Route without Token

    func testProtectedRoute_noToken_returns401() async throws {
        try await app.test(.GET, "vms", afterResponse: { res async throws in
            XCTAssertEqual(res.status, .unauthorized)
        })
    }
}
