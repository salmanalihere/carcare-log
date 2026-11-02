import Foundation
import SwiftData

/// Pure, testable calculation engine. No SwiftData / SwiftUI dependencies.
/// Fuel efficiency uses the full-tank method only: distance between two
/// full-tank fills divided by the fuel added after the first full tank up to
/// and including the second full tank. Anything else returns nil rather than
/// a misleading number.
enum FuelMath {
    struct Fill: Equatable {
        var odometer: Double
        var quantity: Double
        var isFullTank: Bool
        var date: Date
    }

    /// km per unit (L or kWh) across the most recent valid full-to-full segment.
    static func kmPerUnit(fills: [Fill]) -> Double? {
        let sorted = fills.filter { $0.quantity > 0 }.sorted { $0.odometer < $1.odometer }
        let fulls = sorted.indices.filter { sorted[$0].isFullTank }
        guard fulls.count >= 2, let first = fulls.dropLast().last, let last = fulls.last else { return nil }
        let distance = sorted[last].odometer - sorted[first].odometer
        guard distance > 0 else { return nil }
        let consumed = sorted[(first + 1)...last].reduce(0.0) { $0 + $1.quantity }
        guard consumed > 0 else { return nil }
        return distance / consumed
    }

    /// Units per 100 km (L/100 km or kWh/100 km).
    static func unitsPer100km(fills: [Fill]) -> Double? {
        guard let kpu = kmPerUnit(fills: fills), kpu > 0 else { return nil }
        return 100.0 / kpu
    }

    static func totalCost(entries: [(Decimal)]) -> Decimal { entries.reduce(0) { $0 + $1 } }

    /// Cost per km over a period: total fuel cost / distance between first and last odometer in the set.
    static func costPerKilometre(fills: [Fill], totalCost: Decimal) -> Double? {
        let sorted = fills.sorted { $0.odometer < $1.odometer }
        guard let first = sorted.first, let last = sorted.last, sorted.count > 1 else { return nil }
        let d = last.odometer - first.odometer
        guard d > 0 else { return nil }
        return NSDecimalNumber(decimal: totalCost).doubleValue / d
    }

    /// US MPG from km per litre: (km->mi) / (L->US gal) = 2.35214583.
    static let mpgPerKmPerLitre = 2.35214583
    static func mpg(fromKmPerLitre v: Double) -> Double { v * mpgPerKmPerLitre }
    static func kmPerLitre(fromMpg v: Double) -> Double { v / mpgPerKmPerLitre }

    /// Formats efficiency honouring the efficiency-unit preference AND the
    /// distance-unit preference. Internal value is always km per unit (L/kWh).
    /// - unit "kmPerUnit": km/L (or mi/gal-equivalent handling below)
    /// - unit "per100": L/100 km (or L/100 mi when miles are preferred)
    /// - unit "mpg": US miles per gallon (petrol/diesel only)
    static func formattedEfficiency(kmPerUnit value: Double?, unit: String, isElectric: Bool, distanceUnit: String = "km") -> String {
        guard let v = value, v > 0 else { return "Not enough data" }
        let miles = distanceUnit == "mi"
        if isElectric {
            switch unit {
            case "per100":
                return miles ? String(format: "%.1f kWh/100 mi", 160.9344 / v)
                             : String(format: "%.1f kWh/100 km", 100.0 / v)
            default:
                return miles ? String(format: "%.2f mi/kWh", v * 0.6213712)
                             : String(format: "%.2f km/kWh", v)
            }
        }
        switch unit {
        case "per100":
            return miles ? String(format: "%.1f L/100 mi", 160.9344 / v)
                         : String(format: "%.1f L/100 km", 100.0 / v)
        case "mpg":
            return String(format: "%.1f mpg", mpg(fromKmPerLitre: v))
        default:
            // km/L in metric; when the user prefers miles, MPG is the customary unit.
            return miles ? String(format: "%.1f mpg", mpg(fromKmPerLitre: v))
                         : String(format: "%.2f km/L", v)
        }
    }
}

enum ExpenseMath {
    struct Item: Equatable { var amount: Decimal; var date: Date; var category: String }

    static func total(_ items: [Item]) -> Decimal { items.reduce(0) { $0 + $1.amount } }
    static func total(inMonthContaining date: Date, items: [Item], calendar: Calendar = .current) -> Decimal {
        items.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }.reduce(0) { $0 + $1.amount }
    }
    static func monthlyTotals(items: [Item], months: Int = 6, calendar: Calendar = .current, now: Date = .now) -> [(month: Date, total: Decimal)] {
        (0..<months).reversed().map { offset in
            let m = calendar.date(byAdding: .month, value: -offset, to: now) ?? now
            return (month: m, total: total(inMonthContaining: m, items: items, calendar: calendar))
        }
    }
    /// Percentage change of this month vs last month; nil when last month is zero.
    static func monthChangePercent(items: [Item], calendar: Calendar = .current, now: Date = .now) -> Double? {
        let this = NSDecimalNumber(decimal: total(inMonthContaining: now, items: items, calendar: calendar)).doubleValue
        let prevDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let prev = NSDecimalNumber(decimal: total(inMonthContaining: prevDate, items: items, calendar: calendar)).doubleValue
        guard prev > 0 else { return nil }
        return (this - prev) / prev * 100.0
    }
    static func categoryBreakdown(items: [Item]) -> [(category: String, total: Decimal)] {
        var map: [String: Decimal] = [:]
        for i in items { map[i.category, default: 0] += i.amount }
        return map.map { (category: $0.key, total: $0.value) }.sorted { $0.total > $1.total }
    }
    static func averageMonthly(items: [Item]) -> Decimal {
        guard let earliestDate = items.map(\.date).min(),
              let latestDate = items.map(\.date).max() else {
            return 0
        }

        let months = Swift.max(
            1,
            Calendar.current.dateComponents(
                [.month],
                from: earliestDate,
                to: latestDate
            ).month ?? 0
        )

        return total(items) / Decimal(months + 1)
    }
}

enum MaintenanceMath {
    enum Status: String, Equatable { case upcoming, dueSoon, overdue, completed }

    /// Status from whichever of date / odometer limits exist.
    /// Due soon: within 30 days or 1,000 km. Overdue: past either limit.
    static func status(isCompleted: Bool, dueDate: Date?, dueOdometer: Double?,
                       currentOdometer: Double, now: Date = .now) -> Status {
        if isCompleted { return .completed }
        var result: Status = .upcoming
        if let d = dueDate {
            let days = Calendar.current.dateComponents([.day], from: now, to: d).day ?? 0
            if days < 0 { return .overdue }
            if days <= 30 { result = .dueSoon }
        }
        if let o = dueOdometer {
            let remaining = o - currentOdometer
            if remaining < 0 { return .overdue }
            if remaining <= 1000 { result = .dueSoon }
        }
        return result
    }
    static func remainingKilometres(dueOdometer: Double?, currentOdometer: Double) -> Double? {
        guard let o = dueOdometer else { return nil }
        return o - currentOdometer
    }
    static func remainingDays(dueDate: Date?, now: Date = .now) -> Int? {
        guard let d = dueDate else { return nil }
        return Calendar.current.dateComponents([.day], from: now, to: d).day
    }
}

enum MileageValidator {
    /// A new reading must be non-negative and not below the vehicle's latest known reading.
    static func isValid(newReading: Double, latestKnown: Double) -> Bool {
        newReading >= 0 && newReading >= latestKnown
    }
}

/// Distance conversion. INTERNAL BASE UNIT IS KILOMETRES: every stored
/// odometer value in SwiftData is kilometres, always. Conversion happens
/// only at the display/input boundary — changing the preference never
/// rewrites stored data.
enum DistanceUnit {
    static let kmPerMile = 1.609344
    static func displayValue(km: Double, unit: String) -> Double {
        unit == "mi" ? km / kmPerMile : km
    }
    static func storedValue(display: Double, unit: String) -> Double {
        unit == "mi" ? display * kmPerMile : display
    }
    static func label(_ unit: String) -> String { unit == "mi" ? "mi" : "km" }
    static func formatted(km: Double, unit: String) -> String {
        "\(Int(displayValue(km: km, unit: unit).rounded())) \(label(unit))"
    }
}

/// Chronological mileage validation and distance math (FIX 5/7).
///
/// Deterministic ordering rule: entries sort by (date, odometer, id).
/// For a candidate at date X, the PREVIOUS reading is the entry with the
/// greatest date < X (ties on that date: greatest odometer), also considering
/// same-date entries with odometer <= candidate. The NEXT reading is the
/// entry with the smallest date > X (ties: smallest odometer), also
/// considering same-date entries with odometer >= candidate.
/// Valid iff previous <= candidate <= next (for whichever exist).
enum MileageMath {
    struct Reading: Equatable { var id: UUID; var date: Date; var odometer: Double }

    static func sorted(_ readings: [Reading]) -> [Reading] {
        readings.sorted { ($0.date, $0.odometer, $0.id.uuidString) < ($1.date, $1.odometer, $1.id.uuidString) }
    }

    static func isValid(candidateDate: Date, candidateOdometer: Double, excludingID: UUID? = nil, in readings: [Reading], now: Date = .now) -> Bool {
        guard candidateOdometer >= 0 else { return false }
        // A mileage entry can never be dated in the future (enforced here at
        // the service layer, so every caller — manual, edit, automatic — is covered).
        guard candidateDate <= now else { return false }
        let others = readings.filter { $0.id != excludingID }
        var previous: Double? = nil
        var next: Double? = nil
        for r in others {
            if r.date < candidateDate || (r.date == candidateDate && r.odometer <= candidateOdometer) {
                if previous == nil || r.odometer > previous! { previous = r.odometer }
            }
            if r.date > candidateDate || (r.date == candidateDate && r.odometer >= candidateOdometer) {
                if next == nil || r.odometer < next! { next = r.odometer }
            }
        }
        // Same-date entries at exactly the candidate value count as both sides; they are consistent.
        if let p = previous, candidateOdometer < p { return false }
        if let n = next, candidateOdometer > n { return false }
        return true
    }

    /// Exact duplicate = same vehicle (the readings passed in are one
    /// vehicle's), same date/time AND same odometer. Editing an entry does
    /// not count the entry itself (pass its id as excludingID).
    static func hasExactDuplicate(candidateDate: Date, candidateOdometer: Double, excludingID: UUID? = nil, in readings: [Reading]) -> Bool {
        readings.contains { $0.id != excludingID && $0.date == candidateDate && $0.odometer == candidateOdometer }
    }

    /// Distance driven in the month containing `date`:
    /// latest reading in the month minus the last reading at/before the
    /// month start. Returns nil when there is no valid baseline (FIX 7) —
    /// a single reading never produces a misleading distance.
    static func monthlyDistance(readings: [Reading], containing date: Date = .now, calendar: Calendar = .current) -> Double? {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        let ordered = sorted(readings)
        let inPeriod = ordered.filter { interval.contains($0.date) }
        guard let latest = inPeriod.last else { return nil }
        guard let baseline = ordered.filter({ $0.date <= interval.start }).last else { return nil }
        if baseline.date == latest.date && baseline.odometer == latest.odometer { return nil }
        let d = latest.odometer - baseline.odometer
        return d >= 0 ? d : nil
    }
}

/// Centralized money math (FIX 11). EVERY screen uses this service so all
/// totals agree: Total Ownership Cost = Fuel + Expenses + Maintenance.
struct FinancialTotals: Equatable {
    var fuel: Decimal = 0
    var expenses: Decimal = 0
    var maintenance: Decimal = 0
    var ownership: Decimal { fuel + expenses + maintenance }
}

enum FinancialCalculationService {
    static func totals(fuel: [FuelEntry], expenses: [Expense], maintenance: [MaintenanceRecord]) -> FinancialTotals {
        FinancialTotals(
            fuel: fuel.reduce(0) { $0 + Money.dec($1.totalStr) },
            expenses: expenses.reduce(0) { $0 + $1.amount },
            maintenance: maintenance.reduce(0) { $0 + $1.amount })
    }

    static func totals(for vehicle: Vehicle, where include: (Date) -> Bool = { _ in true }) -> FinancialTotals {
        totals(fuel: vehicle.fuelEntries.filter { include($0.date) },
               expenses: vehicle.expenses.filter { include($0.date) },
               maintenance: vehicle.maintenanceRecords.filter { include($0.date) })
    }

    static func totals(for vehicle: Vehicle, in interval: DateInterval?) -> FinancialTotals {
        guard let interval else { return totals(for: vehicle) }
        return totals(for: vehicle) { interval.contains($0) }
    }

    /// Ownership totals per month (oldest -> newest), for charts.
    static func monthlyTotals(for vehicle: Vehicle, months: Int = 6, calendar: Calendar = .current, now: Date = .now) -> [(month: Date, total: Decimal)] {
        (0..<months).reversed().map { offset in
            let m = calendar.date(byAdding: .month, value: -offset, to: now) ?? now
            let total = totals(for: vehicle) { calendar.isDate($0, equalTo: m, toGranularity: .month) }.ownership
            return (month: m, total: total)
        }
    }

    /// Category totals with fuel entries counted as Fuel and maintenance
    /// records counted as Regular Servicing — the same mapping everywhere.
    static func categoryTotals(for vehicle: Vehicle) -> [(category: String, total: Decimal)] {
        var items: [ExpenseMath.Item] = []
        items += vehicle.expenses.map { .init(amount: $0.amount, date: $0.date, category: $0.category.rawValue) }
        items += vehicle.fuelEntries.map { .init(amount: Money.dec($0.totalStr), date: $0.date, category: ExpenseCategory.fuel.rawValue) }
        items += vehicle.maintenanceRecords.map { .init(amount: $0.amount, date: $0.date, category: ExpenseCategory.servicing.rawValue) }
        return ExpenseMath.categoryBreakdown(items: items)
    }

    static func averageMonthlyOwnership(for vehicle: Vehicle) -> Decimal {
        let all = vehicle.expenses.map { ExpenseMath.Item(amount: $0.amount, date: $0.date, category: $0.category.rawValue) }
            + vehicle.fuelEntries.map { ExpenseMath.Item(amount: Money.dec($0.totalStr), date: $0.date, category: "Fuel") }
            + vehicle.maintenanceRecords.map { ExpenseMath.Item(amount: $0.amount, date: $0.date, category: "Servicing") }
        return ExpenseMath.averageMonthly(items: all)
    }
}

/// Creates a MileageEntry for an odometer snapshot (e.g. from a fuel or
/// service record) when appropriate: positive reading, chronologically
/// valid, and not a duplicate (same vehicle, date and reading) — FIX 6.
enum MileageService {
    static func recordIfNeeded(vehicle: Vehicle, odometer: Double, date: Date, notes: String, context: ModelContext) {
        guard odometer > 0 else { return }
        guard date <= .now else { return } // never create future-dated mileage from any record type
        if vehicle.mileageEntries.contains(where: { $0.date == date && $0.odometer == odometer }) { return }
        let readings = vehicle.mileageEntries.map { MileageMath.Reading(id: $0.id, date: $0.date, odometer: $0.odometer) }
        guard MileageMath.isValid(candidateDate: date, candidateOdometer: odometer, in: readings) else { return }
        context.insert(MileageEntry(date: date, odometer: odometer, notes: notes, vehicle: vehicle))
        if odometer > vehicle.odometer { vehicle.odometer = odometer }
    }
}
