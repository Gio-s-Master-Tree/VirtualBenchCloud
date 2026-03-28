import Vapor

/// Registers all routes with the application.
public func routes(_ app: Application) throws {
    // MARK: - Health Check (unauthenticated)

    app.get("health") { req -> [String: String] in
        ["status": "ok", "service": "VirtualBenchCloud"]
    }

    // MARK: - Auth Routes (unauthenticated)

    try app.register(collection: AuthController())

    // MARK: - Authenticated Route Group

    let protected = app.grouped(JWTAuthMiddleware())

    // VM CRUD & lifecycle
    try protected.register(collection: VMController(
        orchestrator: app.orchestrator,
        instanceManager: app.instanceManager
    ))

    // Provision status & streaming
    try protected.register(collection: ProvisionController())

    // Metrics
    try protected.register(collection: MetricsController(
        instanceManager: app.instanceManager
    ))

    // Billing
    try protected.register(collection: BillingController())

    // Display proxy (WebSocket — authentication handled inside the handler via token param)
    try app.register(collection: DisplayProxyController(
        displayProxy: app.displayProxy,
        instanceManager: app.instanceManager
    ))
}
