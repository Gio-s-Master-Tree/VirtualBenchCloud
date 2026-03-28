import Vapor
import Fluent
import FluentPostgresDriver
import JWT

/// Configures the Vapor application: database, JWT, middleware, migrations, and services.
public func configure(_ app: Application) async throws {
    // MARK: - Database

    let databaseURL = Environment.get("DATABASE_URL")
    if let databaseURL = databaseURL {
        try app.databases.use(.postgres(url: databaseURL), as: .psql)
    } else {
        app.databases.use(
            .postgres(
                hostname: Environment.get("DB_HOST") ?? "localhost",
                port: Environment.get("DB_PORT").flatMap(Int.init) ?? 5432,
                username: Environment.get("DB_USER") ?? "virtualbench",
                password: Environment.get("DB_PASSWORD") ?? "virtualbench",
                database: Environment.get("DB_NAME") ?? "virtualbench"
            ),
            as: .psql
        )
    }

    // MARK: - JWT

    let jwtSecret = Environment.get("JWT_SECRET") ?? "dev-secret-change-in-production-32chars!"
    await app.jwt.keys.add(hmac: HMACKey(from: Data(jwtSecret.utf8)), digestAlgorithm: .sha256)

    // MARK: - Migrations

    app.migrations.add(CreateUser())
    app.migrations.add(CreateCloudVM())
    app.migrations.add(CreateProvisionJob())
    app.migrations.add(CreateUsageRecord())

    // Auto-migrate in development
    if app.environment != .production {
        try await app.autoMigrate()
    }

    // MARK: - Global Middleware

    app.middleware.use(RateLimitMiddleware(maxRequests: 100, windowSeconds: 60))

    // CORS configuration
    let corsMiddleware = CORSMiddleware(configuration: .init(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .DELETE, .PATCH, .OPTIONS],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith],
        allowCredentials: false
    ))
    app.middleware.use(corsMiddleware, at: .beginning)

    // MARK: - Services (registered in app.storage for controller access)

    let orchestrator = OrchestratorService()
    let instanceManager = InstanceManager()
    let displayProxy = DisplayProxyService()

    app.storage[OrchestratorServiceKey.self] = orchestrator
    app.storage[InstanceManagerKey.self] = instanceManager
    app.storage[DisplayProxyServiceKey.self] = displayProxy

    // MARK: - Routes

    try routes(app)

    app.logger.info("VirtualBench Cloud API configured successfully.")
}

// MARK: - Storage Keys

struct OrchestratorServiceKey: StorageKey {
    typealias Value = OrchestratorService
}

struct InstanceManagerKey: StorageKey {
    typealias Value = InstanceManager
}

struct DisplayProxyServiceKey: StorageKey {
    typealias Value = DisplayProxyService
}

// MARK: - Application convenience accessors

extension Application {
    var orchestrator: OrchestratorService {
        guard let service = storage[OrchestratorServiceKey.self] else {
            fatalError("OrchestratorService not configured. Call configure() first.")
        }
        return service
    }

    var instanceManager: InstanceManager {
        guard let service = storage[InstanceManagerKey.self] else {
            fatalError("InstanceManager not configured. Call configure() first.")
        }
        return service
    }

    var displayProxy: DisplayProxyService {
        guard let service = storage[DisplayProxyServiceKey.self] else {
            fatalError("DisplayProxyService not configured. Call configure() first.")
        }
        return service
    }
}
