import Vapor
import JWT
import Fluent

/// Handles Sign in with Apple authentication and JWT token management.
struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("signin", use: signIn)
        auth.post("refresh", use: refresh)
    }

    // MARK: - Sign In with Apple

    /// Verifies an Apple identity token and issues JWT access + refresh tokens.
    ///
    /// In production this would fetch Apple's JWKS keys and validate the identity token signature.
    /// For the simulated environment, we decode the token payload without full Apple JWKS verification
    /// and create or fetch the corresponding user.
    @Sendable
    func signIn(req: Request) async throws -> AuthResponse {
        let body = try req.content.decode(SignInRequest.self)

        // Decode the Apple identity token (Base64-encoded JWT).
        // In production: verify via Apple JWKS at https://appleid.apple.com/auth/keys
        let applePayload = try decodeAppleToken(body.identityToken)

        // Find or create user
        let user: User
        if let existing = try await User.query(on: req.db)
            .filter(\.$appleUserID == applePayload.sub)
            .first() {
            user = existing
        } else {
            user = User(
                appleUserID: applePayload.sub,
                email: applePayload.email,
                displayName: applePayload.email ?? "User"
            )
            try await user.save(on: req.db)
        }

        guard let userID = user.id else {
            throw Abort(.internalServerError, reason: "Failed to persist user.")
        }

        let tokens = try generateTokens(userID: userID, tier: user.tier, req: req)
        req.logger.info("User signed in: \(userID)")

        return AuthResponse(
            accessToken: tokens.access,
            refreshToken: tokens.refresh,
            user: UserDTO(from: user)
        )
    }

    // MARK: - Refresh Token

    @Sendable
    func refresh(req: Request) async throws -> TokenResponse {
        let body = try req.content.decode(RefreshTokenRequest.self)

        let payload: RefreshTokenPayload
        do {
            payload = try await req.jwt.verify(body.refreshToken, as: RefreshTokenPayload.self)
        } catch {
            throw Abort(.unauthorized, reason: "Invalid or expired refresh token.")
        }

        guard let user = try await User.find(payload.userID, on: req.db) else {
            throw Abort(.unauthorized, reason: "User not found.")
        }

        let tokens = try generateTokens(userID: user.id!, tier: user.tier, req: req)

        return TokenResponse(
            accessToken: tokens.access,
            refreshToken: tokens.refresh
        )
    }

    // MARK: - Helpers

    /// Generates an access + refresh token pair.
    private func generateTokens(userID: UUID, tier: UserTier, req: Request) throws -> (access: String, refresh: String) {
        let now = Date()

        let accessPayload = AccessTokenPayload(
            sub: SubjectClaim(value: userID.uuidString),
            exp: ExpirationClaim(value: now.addingTimeInterval(15 * 60)), // 15 min
            iat: IssuedAtClaim(value: now),
            userID: userID,
            tier: tier
        )

        let refreshPayload = RefreshTokenPayload(
            sub: SubjectClaim(value: userID.uuidString),
            exp: ExpirationClaim(value: now.addingTimeInterval(30 * 24 * 60 * 60)), // 30 days
            iat: IssuedAtClaim(value: now),
            userID: userID
        )

        let accessToken = try req.jwt.sign(accessPayload)
        let refreshToken = try req.jwt.sign(refreshPayload)

        return (accessToken, refreshToken)
    }

    /// Minimal Apple identity token decoder.
    /// In production, replace with full JWKS verification against Apple's public keys.
    private func decodeAppleToken(_ token: String) throws -> AppleIdentityPayload {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else {
            // Treat the entire token as a simulated Apple user ID
            return AppleIdentityPayload(sub: token, email: nil)
        }

        // Decode the payload segment (index 1)
        var base64 = String(segments[1])
        // Pad to multiple of 4
        while base64.count % 4 != 0 {
            base64 += "="
        }

        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(AppleIdentityPayload.self, from: data) else {
            // Fall back: use the raw token as user ID
            return AppleIdentityPayload(sub: token, email: nil)
        }

        return payload
    }
}

/// Decoded payload from an Apple identity token.
private struct AppleIdentityPayload: Decodable {
    let sub: String
    let email: String?
}
