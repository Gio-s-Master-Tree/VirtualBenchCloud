import Vapor
import JWT
import Fluent

/// Extracts and verifies a JWT Bearer token from the Authorization header,
/// then attaches the authenticated `User` to the request for downstream handlers.
struct JWTAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        // Extract the Bearer token
        guard let bearerToken = request.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Missing authorization token.")
        }

        // Verify and decode the JWT payload
        let payload: AccessTokenPayload
        do {
            payload = try await request.jwt.verify(bearerToken, as: AccessTokenPayload.self)
        } catch {
            throw Abort(.unauthorized, reason: "Invalid or expired access token.")
        }

        // Look up the user
        guard let user = try await User.find(payload.userID, on: request.db) else {
            throw Abort(.unauthorized, reason: "User not found.")
        }

        // Attach the user to the request storage for downstream access
        request.auth.login(user)

        return try await next.respond(to: request)
    }
}

// MARK: - Authenticatable conformance

extension User: Authenticatable {}

// MARK: - Convenience accessor

extension Request {
    /// Returns the authenticated user or throws 401.
    func requireAuthUser() throws -> User {
        guard let user = auth.get(User.self) else {
            throw Abort(.unauthorized, reason: "Authentication required.")
        }
        return user
    }
}
