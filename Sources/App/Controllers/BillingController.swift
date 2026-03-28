import Vapor
import Fluent

/// Billing endpoints: current usage, history, and cost estimation.
struct BillingController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let billing = routes.grouped("billing")
        billing.get("usage", use: currentUsage)
        billing.get("history", use: billingHistory)
        billing.get("estimate", use: costEstimate)
    }

    // MARK: - GET /billing/usage — Current billing period summary

    @Sendable
    func currentUsage(req: Request) async throws -> CurrentBillingPeriodDTO {
        let user = try req.requireAuthUser()
        return try await BillingService.currentPeriodSummary(userID: user.id!, on: req.db)
    }

    // MARK: - GET /billing/history — Past billing periods

    @Sendable
    func billingHistory(req: Request) async throws -> [BillingPeriodDTO] {
        let user = try req.requireAuthUser()
        return try await BillingService.billingHistory(userID: user.id!, on: req.db)
    }

    // MARK: - GET /billing/estimate — Projected monthly cost

    @Sendable
    func costEstimate(req: Request) async throws -> CostEstimateDTO {
        let user = try req.requireAuthUser()
        let estimate = try await BillingService.estimateMonthlyCost(userID: user.id!, on: req.db)
        return CostEstimateDTO(estimatedMonthlyCostCents: estimate)
    }
}
