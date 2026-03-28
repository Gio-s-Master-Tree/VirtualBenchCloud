import Vapor
import Foundation

/// In-memory rate limiter: 100 requests per minute per authenticated user (or per IP for unauthenticated).
/// In production, swap for Redis-backed rate limiting.
final class RateLimitMiddleware: AsyncMiddleware, Sendable {
    /// Thread-safe bucket store.
    private let store: RateLimitStore

    /// Maximum requests allowed per window.
    private let maxRequests: Int

    /// Sliding window size in seconds.
    private let windowSeconds: Int

    init(maxRequests: Int = 100, windowSeconds: Int = 60) {
        self.maxRequests = maxRequests
        self.windowSeconds = windowSeconds
        self.store = RateLimitStore()
    }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let key: String
        if let user = request.auth.get(User.self), let id = user.id {
            key = "user:\(id.uuidString)"
        } else {
            key = "ip:\(request.remoteAddress?.description ?? "unknown")"
        }

        let now = Date()
        let allowed = await store.recordRequest(key: key, now: now, windowSeconds: windowSeconds, maxRequests: maxRequests)

        guard allowed else {
            let response = Response(status: .tooManyRequests)
            response.headers.add(name: .retryAfter, value: "\(windowSeconds)")
            try response.content.encode(
                ErrorResponse(error: true, reason: "Rate limit exceeded. Try again in \(windowSeconds) seconds."),
                as: .json
            )
            return response
        }

        let remaining = await store.remaining(key: key, now: now, windowSeconds: windowSeconds, maxRequests: maxRequests)
        var response = try await next.respond(to: request)
        response.headers.add(name: "X-RateLimit-Limit", value: "\(maxRequests)")
        response.headers.add(name: "X-RateLimit-Remaining", value: "\(remaining)")
        return response
    }
}

// MARK: - In-memory store (actor for thread safety)

private actor RateLimitStore {
    /// Maps key → list of request timestamps in the current window.
    private var buckets: [String: [Date]] = [:]

    /// Periodically prune stale entries (every 1000 calls).
    private var callCount = 0

    func recordRequest(key: String, now: Date, windowSeconds: Int, maxRequests: Int) -> Bool {
        prune(now: now, windowSeconds: windowSeconds)

        var timestamps = buckets[key, default: []]
        let windowStart = now.addingTimeInterval(-Double(windowSeconds))
        timestamps = timestamps.filter { $0 > windowStart }

        if timestamps.count >= maxRequests {
            buckets[key] = timestamps
            return false
        }

        timestamps.append(now)
        buckets[key] = timestamps
        return true
    }

    func remaining(key: String, now: Date, windowSeconds: Int, maxRequests: Int) -> Int {
        let windowStart = now.addingTimeInterval(-Double(windowSeconds))
        let timestamps = (buckets[key] ?? []).filter { $0 > windowStart }
        return max(0, maxRequests - timestamps.count)
    }

    private func prune(now: Date, windowSeconds: Int) {
        callCount += 1
        guard callCount % 1000 == 0 else { return }
        let windowStart = now.addingTimeInterval(-Double(windowSeconds))
        for (key, timestamps) in buckets {
            let filtered = timestamps.filter { $0 > windowStart }
            if filtered.isEmpty {
                buckets.removeValue(forKey: key)
            } else {
                buckets[key] = filtered
            }
        }
    }
}
