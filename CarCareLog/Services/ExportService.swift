import Foundation
import UIKit

// MARK: - CSV

/// One filtered dataset shared by the Reports preview, the PDF and the CSV
/// (FIX 9/14/15): same records, same totals, everywhere.
struct ReportDataset {
    var vehicle: Vehicle
    var periodLabel: String
    var fuel: [FuelEntry]
    var expenses: [Expense]
    var maintenance: [MaintenanceRecord]
    var totals: FinancialTotals { FinancialCalculationService.totals(fuel: fuel, expenses: expenses, maintenance: maintenance) }

    static func make(vehicle: Vehicle, periodLabel: String, range: DateInterval?) -> ReportDataset {
        func keep(_ d: Date) -> Bool { range?.contains(d) ?? true }
        return ReportDataset(vehicle: vehicle, periodLabel: periodLabel,
                             fuel: vehicle.fuelEntries.filter { keep($0.date) }.sorted { $0.date < $1.date },
                             expenses: vehicle.expenses.filter { keep($0.date) }.sorted { $0.date < $1.date },
                             maintenance: vehicle.maintenanceRecords.filter { keep($0.date) }.sorted { $0.date < $1.date })
    }
}

enum CSVExporter {
    static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    /// Full report CSV: Fuel + Expense + Maintenance rows from ONE filtered
    /// dataset, plus summary rows whose totals match the PDF exactly (FIX 13/15).
    static func reportCSV(dataset: ReportDataset) -> String {
        var rows = ["Type,Date,Vehicle,Description,Category,Odometer,Amount,Provider,Notes"]
        let df = ISO8601DateFormatter()
        let vName = escape(dataset.vehicle.displayName)
        for f in dataset.fuel {
            rows.append(["Fuel", df.string(from: f.date), vName, "Fuel (\(f.fuelType.rawValue))", ExpenseCategory.fuel.rawValue,
                         String(format: "%.0f", f.odometer), f.totalStr, escape(f.station), escape(f.notes)].joined(separator: ","))
        }
        for e in dataset.expenses {
            rows.append(["Expense", df.string(from: e.date), vName, escape(e.title), e.category.rawValue,
                         String(format: "%.0f", e.odometer), Money.str(e.amount), escape(e.provider), escape(e.notes)].joined(separator: ","))
        }
        for m in dataset.maintenance {
            rows.append(["Maintenance", df.string(from: m.date), vName, escape(m.title), m.category.rawValue,
                         String(format: "%.0f", m.odometer), Money.str(m.amount), escape(m.provider), escape(m.notes)].joined(separator: ","))
        }
        let t = dataset.totals
        rows.append("Summary,,,,Fuel total,,\(Money.str(t.fuel)),,")
        rows.append("Summary,,,,Expenses total,,\(Money.str(t.expenses)),,")
        rows.append("Summary,,,,Maintenance total,,\(Money.str(t.maintenance)),,")
        rows.append("Summary,,,,Total ownership cost,,\(Money.str(t.ownership)),,")
        return rows.joined(separator: "\n")
    }

    static func writeTempCSV(_ csv: String, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try csv.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
}

// MARK: - PDF report (real vector drawing with UIGraphicsPDFRenderer)

enum PDFReportService {
    /// Paginated report: every page carries the same header and a
    /// "Page X of N" footer. Rendering runs twice — the first pass counts
    /// pages, the second draws with the real total. A section heading is
    /// only placed when at least one row fits beneath it on the same page.
    static func makeReport(vehicle: Vehicle, dataset: ReportDataset, currency: String, distanceUnit: String = "km") -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let counter = UIGraphicsPDFRenderer(bounds: pageRect)
        var totalPages = 1
        _ = counter.pdfData { ctx in
            totalPages = render(ctx: ctx, vehicle: vehicle, dataset: dataset, currency: currency, distanceUnit: distanceUnit, totalPages: nil)
        }
        return renderer.pdfData { ctx in
            _ = render(ctx: ctx, vehicle: vehicle, dataset: dataset, currency: currency, distanceUnit: distanceUnit, totalPages: totalPages)
        }
    }

    /// Draws the whole report; returns the number of pages used.
    /// When `totalPages` is nil the footer is skipped (counting pass).
    private static func render(ctx: UIGraphicsPDFRendererContext, vehicle: Vehicle, dataset: ReportDataset,
                               currency: String, distanceUnit: String, totalPages: Int?) -> Int {
        let expenses = dataset.expenses
        let fuel = dataset.fuel
        let maintenance = dataset.maintenance
        let totals = dataset.totals
        let bottomLimit: CGFloat = 730   // footer sits at 756; content never reaches it
        var page = 0
        var y: CGFloat = 0

        func draw(_ text: String, x: CGFloat, yPos: CGFloat, size: CGFloat, bold: Bool = false) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size),
                .foregroundColor: UIColor.label
            ]
            text.draw(at: CGPoint(x: x, y: yPos), withAttributes: attrs)
        }
        func beginPage() {
            ctx.beginPage()
            page += 1
            // Consistent header on EVERY page.
            draw("CarCare Log \u{2014} Vehicle Report", x: 48, yPos: 36, size: 13, bold: true)
            draw("\(vehicle.displayName) \u{00B7} \(dataset.periodLabel)", x: 48, yPos: 54, size: 10)
            if let totalPages {
                let footer = "Page \(page) of \(totalPages)"
                let width = (footer as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 10)]).width
                draw(footer, x: (612 - width) / 2, yPos: 756, size: 10)
            }
            y = 78
        }
        func line(_ s: String, size: CGFloat = 11, bold: Bool = false, dy: CGFloat = 18) {
            if y + dy > bottomLimit { beginPage() }
            draw(s, x: 48, yPos: y, size: size, bold: bold)
            y += dy
        }
        func section(_ title: String) {
            // Heading + at least one row must fit, otherwise start a new page.
            if y + 22 + 16 > bottomLimit { beginPage() }
            draw(title, x: 48, yPos: y, size: 15, bold: true)
            y += 24
        }

        beginPage()
        let df = DateFormatter(); df.dateStyle = .medium
        line("\(vehicle.displayName) \u{00B7} \(vehicle.brand) \(vehicle.model) (\(vehicle.year))", size: 13, bold: true, dy: 20)
        line("Registration: \(vehicle.registrationNumber)   Odometer: \(DistanceUnit.formatted(km: vehicle.latestOdometer, unit: distanceUnit))")
        line("Period: \(dataset.periodLabel)")
        line("Total ownership cost: \(Money.format(Money.str(totals.ownership), currency: currency))", size: 13, bold: true, dy: 10)
        line("Fuel: \(Money.format(Money.str(totals.fuel), currency: currency))   Expenses: \(Money.format(Money.str(totals.expenses), currency: currency))   Maintenance: \(Money.format(Money.str(totals.maintenance), currency: currency))", dy: 26)

        section("Expenses")
        if expenses.isEmpty { line("No expense records in this period.", dy: 16) }
        for e in expenses {
            line("\(df.string(from: e.date))  \(e.title) (\(e.category.rawValue))  \(Money.format(e.amountStr, currency: currency))", dy: 16)
        }
        y += 8
        section("Fuel")
        if fuel.isEmpty { line("No fuel records in this period.", dy: 16) }
        for f in fuel {
            line("\(df.string(from: f.date))  \(f.quantity) \(f.fuelType.unitLabel) @ \(DistanceUnit.formatted(km: f.odometer, unit: distanceUnit))  \(Money.format(f.totalStr, currency: currency))", dy: 16)
        }
        y += 8
        section("Maintenance History")
        if maintenance.isEmpty { line("No maintenance records in this period.", dy: 16) }
        for m in maintenance {
            line("\(df.string(from: m.date))  \(m.title) (\(m.category.rawValue))  \(Money.format(m.amountStr, currency: currency))", dy: 16)
        }
        y += 16
        line("Grand total: \(Money.format(Money.str(totals.ownership), currency: currency))", size: 13, bold: true)
        return page
    }
}

// MARK: - Backup (current format: v3) with v1/v2 backward compatibility
//
// Format history:
//  v1 (1.0.0): vehicles with fuel/expenses/maintenance only, no photos,
//              no schedules/reminders/documents, several fields missing.
//  v2 (1.0.1): everything in v1 plus all vehicle fields, photos and receipt
//              images (base64), schedules, reminders, documents + attachments, IDs.
//  v3 (1.0.2): v2 plus MileageEntry records.
// All v2-only fields are Optional in the DTOs so a v1 file still decodes;
// BackupValidator checks the fully-decoded DTO before anything is inserted,
// so a bad file can never partially modify the database.

struct BackupDTO: Codable {
    var formatVersion: Int? = nil
    var exportedAt: Date
    var vehicles: [VehicleDTO]
    var effectiveVersion: Int { formatVersion ?? 1 }

    struct VehicleDTO: Codable {
        var id: String? = nil
        var name: String; var brand: String; var model: String; var year: Int
        var registrationNumber: String; var vehicleType: String; var fuelType: String; var odometer: Double
        var vin: String; var notes: String
        var engineNumber: String? = nil
        var purchaseDate: Date? = nil; var purchasePrice: String? = nil
        var insuranceProvider: String? = nil; var insuranceExpiry: Date? = nil; var registrationExpiry: Date? = nil
        var createdAt: Date? = nil
        var photoBase64: String? = nil
        var fuel: [FuelDTO]; var expenses: [ExpenseDTO]; var maintenance: [MaintenanceDTO]
        var schedules: [ScheduleDTO]? = nil
        var reminders: [ReminderDTO]? = nil
        var documents: [DocumentDTO]? = nil
        var mileage: [MileageDTO]? = nil
    }
    struct MileageDTO: Codable {
        var id: String? = nil
        var date: Date; var odometer: Double; var notes: String? = nil
    }
    struct FuelDTO: Codable {
        var id: String? = nil
        var date: Date; var odometer: Double; var quantity: Double; var total: String; var station: String; var isFullTank: Bool
        var fuelType: String? = nil; var pricePerUnit: String? = nil; var notes: String? = nil; var receiptBase64: String? = nil
    }
    struct ExpenseDTO: Codable {
        var id: String? = nil
        var title: String; var category: String; var amount: String; var date: Date; var provider: String
        var odometer: Double? = nil; var notes: String? = nil; var receiptBase64: String? = nil
    }
    struct MaintenanceDTO: Codable {
        var id: String? = nil
        var title: String; var category: String; var date: Date; var odometer: Double; var amount: String
        var provider: String? = nil; var nextDate: Date? = nil; var nextOdometer: Double? = nil
        var notes: String? = nil; var receiptBase64: String? = nil
    }
    struct ScheduleDTO: Codable {
        var id: String? = nil
        var title: String; var category: String; var dueDate: Date?; var dueOdometer: Double?
        var isCompleted: Bool; var reminderLeadDays: Int; var notificationsEnabled: Bool
        var notes: String; var createdAt: Date? = nil
    }
    struct ReminderDTO: Codable {
        var id: String? = nil
        var title: String; var kind: String; var date: Date?; var odometerTarget: Double?
        var leadDays: Int; var isEnabled: Bool
    }
    struct DocumentDTO: Codable {
        var id: String? = nil
        var name: String; var type: String; var issueDate: Date?; var expiryDate: Date?
        var notes: String; var fileBase64: String? = nil; var fileExtension: String? = nil; var createdAt: Date? = nil
    }
}

enum BackupError: Error, CustomStringConvertible {
    case unsupportedVersion(Int)
    case invalid(String)
    var description: String {
        switch self {
        case .unsupportedVersion(let v): return "Backup format version \(v) is not supported by this app version."
        case .invalid(let m): return m
        }
    }
}

enum BackupValidator {
    static func validate(_ dto: BackupDTO) throws {
        guard (1...3).contains(dto.effectiveVersion) else { throw BackupError.unsupportedVersion(dto.effectiveVersion) }
        for v in dto.vehicles {
            guard (1950...2100).contains(v.year) else { throw BackupError.invalid("Vehicle year \(v.year) is out of range.") }
            guard v.odometer >= 0 else { throw BackupError.invalid("Vehicle odometer cannot be negative.") }
            guard VehicleType(rawValue: v.vehicleType) != nil else { throw BackupError.invalid("Unknown vehicle type: \(v.vehicleType)") }
            guard FuelType(rawValue: v.fuelType) != nil else { throw BackupError.invalid("Unknown fuel type: \(v.fuelType)") }
            if let p = v.purchasePrice, Money.dec(p) < 0 { throw BackupError.invalid("Purchase price cannot be negative.") }
            if let b64 = v.photoBase64, Data(base64Encoded: b64) == nil { throw BackupError.invalid("Vehicle photo data is corrupted.") }
            for f in v.fuel {
                guard f.quantity > 0 else { throw BackupError.invalid("A fuel entry has a non-positive quantity.") }
                guard f.odometer >= 0 else { throw BackupError.invalid("A fuel entry has a negative odometer.") }
                guard Money.dec(f.total) >= 0 else { throw BackupError.invalid("A fuel entry has an invalid total.") }
                if let t = f.fuelType, FuelType(rawValue: t) == nil { throw BackupError.invalid("Unknown fuel type in an entry: \(t)") }
                if let b64 = f.receiptBase64, Data(base64Encoded: b64) == nil { throw BackupError.invalid("A fuel receipt is corrupted.") }
            }
            for e in v.expenses {
                guard ExpenseCategory(rawValue: e.category) != nil else { throw BackupError.invalid("Unknown expense category: \(e.category)") }
                guard Money.dec(e.amount) >= 0, Decimal(string: e.amount) != nil else { throw BackupError.invalid("An expense has an invalid amount.") }
                if let o = e.odometer, o < 0 { throw BackupError.invalid("An expense has a negative odometer.") }
                if let b64 = e.receiptBase64, Data(base64Encoded: b64) == nil { throw BackupError.invalid("An expense receipt is corrupted.") }
            }
            for m in v.maintenance {
                guard MaintenanceCategory(rawValue: m.category) != nil else { throw BackupError.invalid("Unknown maintenance category: \(m.category)") }
                guard m.odometer >= 0 else { throw BackupError.invalid("A maintenance record has a negative odometer.") }
                guard Money.dec(m.amount) >= 0, Decimal(string: m.amount) != nil else { throw BackupError.invalid("A maintenance record has an invalid amount.") }
                if let nd = m.nextDate, nd < m.date { throw BackupError.invalid("A maintenance record's next date precedes its service date.") }
                if let b64 = m.receiptBase64, Data(base64Encoded: b64) == nil { throw BackupError.invalid("A maintenance receipt is corrupted.") }
            }
            for s in v.schedules ?? [] {
                guard MaintenanceCategory(rawValue: s.category) != nil else { throw BackupError.invalid("Unknown schedule category: \(s.category)") }
                guard s.dueDate != nil || s.dueOdometer != nil else { throw BackupError.invalid("Schedule '\(s.title)' has neither a due date nor a due odometer.") }
                if let o = s.dueOdometer, o < 0 { throw BackupError.invalid("Schedule '\(s.title)' has a negative due odometer.") }
                guard [0, 7, 15, 30].contains(s.reminderLeadDays) else { throw BackupError.invalid("Schedule '\(s.title)' has an invalid reminder lead time.") }
            }
            for r in v.reminders ?? [] {
                guard ReminderKind(rawValue: r.kind) != nil else { throw BackupError.invalid("Unknown reminder kind: \(r.kind)") }
                if let o = r.odometerTarget, o < 0 { throw BackupError.invalid("Reminder '\(r.title)' has a negative odometer target.") }
            }
            for m in v.mileage ?? [] {
                guard m.odometer >= 0 else { throw BackupError.invalid("A mileage entry has a negative odometer.") }
                guard m.date <= .now else { throw BackupError.invalid("A mileage entry is dated in the future.") }
            }
            for d in v.documents ?? [] {
                guard DocumentType(rawValue: d.type) != nil else { throw BackupError.invalid("Unknown document type: \(d.type)") }
                if let i = d.issueDate, let e = d.expiryDate, e < i { throw BackupError.invalid("Document '\(d.name)' expires before it was issued.") }
                if let b64 = d.fileBase64, Data(base64Encoded: b64) == nil { throw BackupError.invalid("Document '\(d.name)' attachment is corrupted.") }
            }
        }
    }
}

enum BackupService {
    static let currentFormatVersion = 3

    static func makeBackup(vehicles: [Vehicle]) throws -> Data {
        let dto = BackupDTO(formatVersion: currentFormatVersion, exportedAt: .now, vehicles: vehicles.map { v in
            BackupDTO.VehicleDTO(
                id: v.id.uuidString, name: v.name, brand: v.brand, model: v.model, year: v.year,
                registrationNumber: v.registrationNumber, vehicleType: v.vehicleTypeRaw,
                fuelType: v.fuelTypeRaw, odometer: v.odometer, vin: v.vin, notes: v.notes,
                engineNumber: v.engineNumber, purchaseDate: v.purchaseDate, purchasePrice: v.purchasePriceStr,
                insuranceProvider: v.insuranceProvider, insuranceExpiry: v.insuranceExpiry,
                registrationExpiry: v.registrationExpiry, createdAt: v.createdAt,
                photoBase64: v.photoData?.base64EncodedString(),
                fuel: v.fuelEntries.map { .init(id: $0.id.uuidString, date: $0.date, odometer: $0.odometer, quantity: $0.quantity, total: $0.totalStr, station: $0.station, isFullTank: $0.isFullTank, fuelType: $0.fuelTypeRaw, pricePerUnit: $0.pricePerUnitStr, notes: $0.notes, receiptBase64: $0.receiptData?.base64EncodedString()) },
                expenses: v.expenses.map { .init(id: $0.id.uuidString, title: $0.title, category: $0.categoryRaw, amount: $0.amountStr, date: $0.date, provider: $0.provider, odometer: $0.odometer, notes: $0.notes, receiptBase64: $0.receiptData?.base64EncodedString()) },
                maintenance: v.maintenanceRecords.map { .init(id: $0.id.uuidString, title: $0.title, category: $0.categoryRaw, date: $0.date, odometer: $0.odometer, amount: $0.amountStr, provider: $0.provider, nextDate: $0.nextDate, nextOdometer: $0.nextOdometer, notes: $0.notes, receiptBase64: $0.receiptData?.base64EncodedString()) },
                schedules: v.schedules.map { .init(id: $0.id.uuidString, title: $0.title, category: $0.categoryRaw, dueDate: $0.dueDate, dueOdometer: $0.dueOdometer, isCompleted: $0.isCompleted, reminderLeadDays: $0.reminderLeadDays, notificationsEnabled: $0.notificationsEnabled, notes: $0.notes, createdAt: $0.createdAt) },
                reminders: v.reminders.map { .init(id: $0.id.uuidString, title: $0.title, kind: $0.kindRaw, date: $0.date, odometerTarget: $0.odometerTarget, leadDays: $0.leadDays, isEnabled: $0.isEnabled) },
                documents: v.documents.map { .init(id: $0.id.uuidString, name: $0.name, type: $0.typeRaw, issueDate: $0.issueDate, expiryDate: $0.expiryDate, notes: $0.notes, fileBase64: $0.fileData?.base64EncodedString(), fileExtension: $0.fileExtension, createdAt: $0.createdAt) },
                mileage: v.mileageEntries.map { .init(id: $0.id.uuidString, date: $0.date, odometer: $0.odometer, notes: $0.notes) })
        })
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(dto)
    }

    static func decode(_ data: Data) throws -> BackupDTO {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(BackupDTO.self, from: data)
    }

    /// Builds the complete model graph detached from any ModelContext.
    /// Call ONLY after `BackupValidator.validate` has passed; the caller then
    /// inserts the returned vehicles, so a failed validation changes nothing.
    static func buildVehicles(from dto: BackupDTO) -> [Vehicle] {
        dto.vehicles.map { v in
            let vehicle = Vehicle(name: v.name, brand: v.brand, model: v.model, year: v.year,
                                  registrationNumber: v.registrationNumber,
                                  vehicleType: VehicleType(rawValue: v.vehicleType) ?? .other,
                                  fuelType: FuelType(rawValue: v.fuelType) ?? .petrol,
                                  odometer: v.odometer)
            if let id = v.id, let uuid = UUID(uuidString: id) { vehicle.id = uuid }
            vehicle.vin = v.vin; vehicle.notes = v.notes
            vehicle.engineNumber = v.engineNumber ?? ""
            vehicle.purchaseDate = v.purchaseDate
            vehicle.purchasePriceStr = v.purchasePrice ?? "0"
            vehicle.insuranceProvider = v.insuranceProvider ?? ""
            vehicle.insuranceExpiry = v.insuranceExpiry
            vehicle.registrationExpiry = v.registrationExpiry
            if let c = v.createdAt { vehicle.createdAt = c }
            vehicle.photoData = v.photoBase64.flatMap { Data(base64Encoded: $0) }

            vehicle.fuelEntries = v.fuel.map { f in
                let e = FuelEntry(date: f.date, odometer: f.odometer,
                                  fuelType: FuelType(rawValue: f.fuelType ?? v.fuelType) ?? vehicle.fuelType,
                                  quantity: f.quantity, pricePerUnit: Money.dec(f.pricePerUnit ?? "0"),
                                  total: Money.dec(f.total), station: f.station, isFullTank: f.isFullTank,
                                  notes: f.notes ?? "", vehicle: vehicle)
                if let id = f.id, let uuid = UUID(uuidString: id) { e.id = uuid }
                e.receiptData = f.receiptBase64.flatMap { Data(base64Encoded: $0) }
                return e
            }
            vehicle.expenses = v.expenses.map { x in
                let e = Expense(title: x.title, category: ExpenseCategory(rawValue: x.category) ?? .other,
                                amount: Money.dec(x.amount), date: x.date, odometer: x.odometer ?? 0,
                                provider: x.provider, notes: x.notes ?? "", vehicle: vehicle)
                if let id = x.id, let uuid = UUID(uuidString: id) { e.id = uuid }
                e.receiptData = x.receiptBase64.flatMap { Data(base64Encoded: $0) }
                return e
            }
            vehicle.maintenanceRecords = v.maintenance.map { m in
                let r = MaintenanceRecord(title: m.title, category: MaintenanceCategory(rawValue: m.category) ?? .other,
                                          date: m.date, odometer: m.odometer, provider: m.provider ?? "",
                                          amount: Money.dec(m.amount), nextDate: m.nextDate,
                                          nextOdometer: m.nextOdometer, notes: m.notes ?? "", vehicle: vehicle)
                if let id = m.id, let uuid = UUID(uuidString: id) { r.id = uuid }
                r.receiptData = m.receiptBase64.flatMap { Data(base64Encoded: $0) }
                return r
            }
            vehicle.schedules = (v.schedules ?? []).map { s in
                let sch = MaintenanceSchedule(title: s.title, category: MaintenanceCategory(rawValue: s.category) ?? .other,
                                              dueDate: s.dueDate, dueOdometer: s.dueOdometer,
                                              reminderLeadDays: s.reminderLeadDays, notes: s.notes, vehicle: vehicle)
                if let id = s.id, let uuid = UUID(uuidString: id) { sch.id = uuid }
                sch.isCompleted = s.isCompleted; sch.notificationsEnabled = s.notificationsEnabled
                if let c = s.createdAt { sch.createdAt = c }
                return sch
            }
            vehicle.reminders = (v.reminders ?? []).map { r in
                let rem = ReminderItem(title: r.title, kind: ReminderKind(rawValue: r.kind) ?? .custom,
                                       date: r.date, odometerTarget: r.odometerTarget, leadDays: r.leadDays, vehicle: vehicle)
                if let id = r.id, let uuid = UUID(uuidString: id) { rem.id = uuid }
                rem.isEnabled = r.isEnabled
                return rem
            }
            vehicle.mileageEntries = (v.mileage ?? []).map { m in
                let e = MileageEntry(date: m.date, odometer: m.odometer, notes: m.notes ?? "", vehicle: vehicle)
                if let id = m.id, let uuid = UUID(uuidString: id) { e.id = uuid }
                return e
            }
            vehicle.documents = (v.documents ?? []).map { d in
                let doc = VehicleDocument(name: d.name, type: DocumentType(rawValue: d.type) ?? .other,
                                          issueDate: d.issueDate, expiryDate: d.expiryDate, notes: d.notes, vehicle: vehicle)
                if let id = d.id, let uuid = UUID(uuidString: id) { doc.id = uuid }
                doc.fileData = d.fileBase64.flatMap { Data(base64Encoded: $0) }
                doc.fileExtension = d.fileExtension ?? ""
                if let c = d.createdAt { doc.createdAt = c }
                return doc
            }
            return vehicle
        }
    }
}
