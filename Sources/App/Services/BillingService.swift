import Vapor
import Fluent
import Foundation

/// Handles usage-based billing calculations and record management.
struct BillingService: Sendable {
    /// Calculate cost in cents for a given instance type and duration.
    static func calculateCost(instanceType: String, durationMinutes: Int) -> Int {
        guard let spec = CloudInstanceType.find(instanceType) else { return 0 }
        // centsPerHour / 60 * durationMinutes, rounded up to nearest cent
        let costPerMinute = Double(spec.centsPerHour) / 60.0
        return Int(ceil(costPerMinute * Double(durationMinutes)))
    }

    /// Start tracking usage for a VM. Creates an open-ended UsageRecord.
    static func startTracking(
        userID: UUID,
        vmID: UUID,
        instanceType: String,
        on db: any Database
    ) async throws -> UsageRecord {
        let record = UsageRecord(
            userID: userID,
            vmID: vmID,
            instanceType: instanceType,
            startedAt: Date(),
            durationMinutes: 0,
            costCents: 0
        )
        try await record.save(on: db)
        return record
    }

    /// Stop tracking usage for a VM. Closes the most recent open record.
    static func stopTracking(
        vmID: UUID,
        on db: any Database
    ) async throws {
        guard let record = try await UsageRecord.query(on: db)
            .filter(\.$vm.$id == vmID)
            .filter(\.$endedAt == nil)
            .sort(\.$startedAt, .descending)
            .first()
        else {
            return
        }

        let now = Date()
        let minutes = max(1, Int(now.timeIntervalSince(record.startedAt) / 60.0))
        record.endedAt = now
        record.durationMinutes = minutes
        record.costCents = calculateCost(instanceType: record.instanceType, durationMinutes: minutes)
        try await record.save(on: db)
    }

    /// Get total cost for the current billing period (calendar month).
    static func currentPeriodSummary(
        userID: UUID,
        on db: any Database
    ) async throws -> CurrentBillingPeriodDTO {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        let periodStart = calendar.date(from: components)!
        var nextMonthComponents = components
        nextMonthComponents.month = (nextMonthComponents.month ?? 1) + 1
        let periodEnd = calendar.date(from: nextMonthComponents)!

        let records = try await UsageRecord.query(on: db)
            .filter(\.$user.$id == userID)
            .filter(\.$startedAt >= periodStart)
            .all()

        // For open records, calculate interim cost
        var totalCost = 0
        var totalMinutes = 0
        var dtos: [UsageRecordDTO] = []

        for record in records {
            var dto = UsageRecordDTO(from: record)
            if record.endedAt == nil {
                // Still running — compute interim
                let minutes = max(1, Int(now.timeIntervalSince(record.startedAt) / 60.0))
                let cost = calculateCost(instanceType: record.instanceType, durationMinutes: minutes)
                totalMinutes += minutes
                totalCost += cost
            } else {
                totalMinutes += record.durationMinutes
                totalCost += record.costCents
            }
            dtos.append(dto)
        }

        return CurrentBillingPeriodDTO(
            periodStart: periodStart,
            periodEnd: periodEnd,
            totalCostCents: totalCost,
            totalMinutes: totalMinutes,
            records: dtos
        )
    }

    /// Get billing history (list of past months with totals).
    static func billingHistory(
        userID: UUID,
        on db: any Database
    ) async throws -> [BillingPeriodDTO] {
        let records = try await UsageRecord.query(on: db)
            .filter(\.$user.$id == userID)
            .filter(\.$endedAt != nil)
            .sort(\.$startedAt, .ascending)
            .all()

        // Group by calendar month
        let calendar = Calendar(identifier: .gregorian)
        var months: [String: (start: Date, end: Date, cost: Int, minutes: Int)] = [:]

        for record in records {
            let comps = calendar.dateComponents([.year, .month], from: record.startedAt)
            let key = "\(comps.year!)-\(comps.month!)"
            let monthStart = calendar.date(from: comps)!
            var nextComps = comps
            nextComps.month = (nextComps.month ?? 1) + 1
            let monthEnd = calendar.date(from: nextComps)!

            var entry = months[key, default: (start: monthStart, end: monthEnd, cost: 0, minutes: 0)]
            entry.cost += record.costCents
            entry.minutes += record.durationMinutes
            months[key] = entry
        }

        return months.values
            .sorted { $0.start < $1.start }
            .map { BillingPeriodDTO(periodStart: $0.start, periodEnd: $0.end, totalCostCents: $0.cost, totalMinutes: $0.minutes) }
    }

    /// Estimate monthly cost based on average daily usage in the current period.
    static func estimateMonthlyCost(
        userID: UUID,
        on db: any Database
    ) async throws -> Int {
        let summary = try await currentPeriodSummary(userID: userID, on: db)
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let dayOfMonth = calendar.component(.day, from: now)
        guard dayOfMonth > 0 else { return summary.totalCostCents }

        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let dailyAverage = Double(summary.totalCostCents) / Double(dayOfMonth)
        return Int(ceil(dailyAverage * Double(daysInMonth)))
    }
}
