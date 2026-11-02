import Foundation
import SwiftData

// MARK: - Money (Decimal stored as String for exact SwiftData persistence)

enum Money {
    static func dec(_ s: String) -> Decimal { Decimal(string: s) ?? 0 }
    static func str(_ d: Decimal) -> String { NSDecimalNumber(decimal: d).stringValue }
    static func format(_ s: String, currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        return f.string(from: NSDecimalNumber(decimal: dec(s))) ?? s
    }
}

// MARK: - Enumerations (stored as raw strings)

enum VehicleType: String, CaseIterable, Codable {
    case sedan = "Sedan", suv = "SUV", hatchback = "Hatchback", coupe = "Coupe"
    case convertible = "Convertible", pickup = "Pickup", motorcycle = "Motorcycle", other = "Other"
    var icon: String {
        switch self {
        case .motorcycle: return "figure.outdoor.cycle"
        case .pickup: return "truck.pickup.side.fill"
        default: return "car.fill"
        }
    }
}

enum FuelType: String, CaseIterable, Codable {
    case petrol = "Petrol", diesel = "Diesel", electric = "Electric", hybrid = "Hybrid"
    case cng = "CNG", lpg = "LPG", other = "Other"
    var isElectric: Bool { self == .electric }
    var unitLabel: String { self == .electric ? "kWh" : "L" }
}

enum ExpenseCategory: String, CaseIterable, Codable {
    case fuel = "Fuel", servicing = "Regular Servicing", repairs = "Repairs", insurance = "Insurance"
    case registration = "Registration", parking = "Parking", tolls = "Tolls", carWash = "Car Wash"
    case accessories = "Accessories", tyres = "Tyres", battery = "Battery", other = "Other"
    var icon: String {
        switch self {
        case .fuel: return "fuelpump.fill"
        case .servicing: return "wrench.and.screwdriver.fill"
        case .repairs: return "hammer.fill"
        case .insurance: return "shield.fill"
        case .registration: return "doc.text.fill"
        case .parking: return "parkingsign.circle.fill"
        case .tolls: return "road.lanes"
        case .carWash: return "bubbles.and.sparkles.fill"
        case .accessories: return "bag.fill"
        case .tyres: return "circle.circle.fill"
        case .battery: return "battery.100percent"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

enum MaintenanceCategory: String, CaseIterable, Codable {
    case engineOil = "Engine Oil Replacement", oilFilter = "Oil Filter Replacement"
    case airFilter = "Air Filter Replacement", cabinFilter = "Cabin Filter Replacement"
    case brakePads = "Brake Pads", brakeFluid = "Brake Fluid", coolant = "Coolant"
    case transmissionFluid = "Transmission Fluid", battery = "Battery Replacement"
    case tyres = "Tyre Replacement", wheelAlignment = "Wheel Alignment", sparkPlugs = "Spark Plugs"
    case inspection = "General Inspection", fullService = "Full Vehicle Service", other = "Other"
    var icon: String { "wrench.and.screwdriver.fill" }
}

enum DocumentType: String, CaseIterable, Codable {
    case insurance = "Insurance", registration = "Registration Certificate", purchaseInvoice = "Purchase Invoice"
    case serviceReceipt = "Service Receipt", warranty = "Warranty", pollution = "Pollution Certificate", other = "Other"
}

enum ReminderKind: String, CaseIterable, Codable {
    case maintenance = "Maintenance", insurance = "Insurance", registration = "Registration", custom = "Custom"
}

// MARK: - Vehicle

@Model
final class Vehicle {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    var model: String = ""
    var year: Int = 2020
    var registrationNumber: String = ""
    var vehicleTypeRaw: String = VehicleType.sedan.rawValue
    var fuelTypeRaw: String = FuelType.petrol.rawValue
    var odometer: Double = 0
    @Attribute(.externalStorage) var photoData: Data? = nil
    var vin: String = ""
    var engineNumber: String = ""
    var purchaseDate: Date? = nil
    var purchasePriceStr: String = "0"
    var insuranceProvider: String = ""
    var insuranceExpiry: Date? = nil
    var registrationExpiry: Date? = nil
    var notes: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \FuelEntry.vehicle) var fuelEntries: [FuelEntry] = []
    @Relationship(deleteRule: .cascade, inverse: \Expense.vehicle) var expenses: [Expense] = []
    @Relationship(deleteRule: .cascade, inverse: \MaintenanceRecord.vehicle) var maintenanceRecords: [MaintenanceRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \MaintenanceSchedule.vehicle) var schedules: [MaintenanceSchedule] = []
    @Relationship(deleteRule: .cascade, inverse: \VehicleDocument.vehicle) var documents: [VehicleDocument] = []
    @Relationship(deleteRule: .cascade, inverse: \ReminderItem.vehicle) var reminders: [ReminderItem] = []
    @Relationship(deleteRule: .cascade, inverse: \MileageEntry.vehicle) var mileageEntries: [MileageEntry] = []

    init(name: String, brand: String, model: String, year: Int, registrationNumber: String,
         vehicleType: VehicleType, fuelType: FuelType, odometer: Double) {
        self.name = name; self.brand = brand; self.model = model; self.year = year
        self.registrationNumber = registrationNumber
        self.vehicleTypeRaw = vehicleType.rawValue; self.fuelTypeRaw = fuelType.rawValue
        self.odometer = odometer
    }

    var vehicleType: VehicleType { VehicleType(rawValue: vehicleTypeRaw) ?? .other }
    var fuelType: FuelType { FuelType(rawValue: fuelTypeRaw) ?? .petrol }
    var displayName: String { name.isEmpty ? "\(brand) \(model)".trimmingCharacters(in: .whitespaces) : name }
    /// Current mileage: the chronologically latest MileageEntry when history
    /// exists (FIX 6/8), otherwise the vehicle's stored odometer field.
    /// Fuel/maintenance odometer snapshots are NOT used as mileage history.
    var latestOdometer: Double {
        if !mileageEntries.isEmpty {
            return mileageEntries.sorted { ($0.date, $0.odometer) < ($1.date, $1.odometer) }.last?.odometer ?? odometer
        }
        return odometer
    }
    /// Total ownership cost = Fuel + Expenses + Maintenance (centralized, FIX 11/12).
    var totalExpenses: Decimal { FinancialCalculationService.totals(for: self).ownership }
    // Component subtotals, delegated to the same centralized service (FIX 8).
    var totalFuelExpenses: Decimal { FinancialCalculationService.totals(for: self).fuel }
    var totalMaintenanceExpenses: Decimal { FinancialCalculationService.totals(for: self).maintenance }
}

// MARK: - Mileage history (dedicated, persistent — FIX 1)

@Model
final class MileageEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var odometer: Double = 0   // kilometres, internal base unit
    var notes: String = ""
    var vehicle: Vehicle? = nil

    init(date: Date, odometer: Double, notes: String, vehicle: Vehicle?) {
        self.date = date; self.odometer = odometer; self.notes = notes; self.vehicle = vehicle
    }
}

// MARK: - Fuel

@Model
final class FuelEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var odometer: Double = 0
    var fuelTypeRaw: String = FuelType.petrol.rawValue
    var quantity: Double = 0            // litres or kWh
    var pricePerUnitStr: String = "0"   // Decimal string
    var totalStr: String = "0"          // Decimal string
    var station: String = ""
    var isFullTank: Bool = true
    var notes: String = ""
    @Attribute(.externalStorage) var receiptData: Data? = nil
    var vehicle: Vehicle? = nil

    init(date: Date, odometer: Double, fuelType: FuelType, quantity: Double,
         pricePerUnit: Decimal, total: Decimal, station: String, isFullTank: Bool, notes: String, vehicle: Vehicle?) {
        self.date = date; self.odometer = odometer; self.fuelTypeRaw = fuelType.rawValue
        self.quantity = quantity; self.pricePerUnitStr = Money.str(pricePerUnit)
        self.totalStr = Money.str(total); self.station = station
        self.isFullTank = isFullTank; self.notes = notes; self.vehicle = vehicle
    }
    var fuelType: FuelType { FuelType(rawValue: fuelTypeRaw) ?? .petrol }
}

// MARK: - Expense

@Model
final class Expense {
    var id: UUID = UUID()
    var title: String = ""
    var categoryRaw: String = ExpenseCategory.other.rawValue
    var amountStr: String = "0"
    var date: Date = Date.now
    var odometer: Double = 0
    var provider: String = ""
    var notes: String = ""
    @Attribute(.externalStorage) var receiptData: Data? = nil
    var vehicle: Vehicle? = nil

    init(title: String, category: ExpenseCategory, amount: Decimal, date: Date,
         odometer: Double, provider: String, notes: String, vehicle: Vehicle?) {
        self.title = title; self.categoryRaw = category.rawValue; self.amountStr = Money.str(amount)
        self.date = date; self.odometer = odometer; self.provider = provider
        self.notes = notes; self.vehicle = vehicle
    }
    var category: ExpenseCategory { ExpenseCategory(rawValue: categoryRaw) ?? .other }
    var amount: Decimal { Money.dec(amountStr) }
}

// MARK: - Maintenance

@Model
final class MaintenanceRecord {
    var id: UUID = UUID()
    var title: String = ""
    var categoryRaw: String = MaintenanceCategory.other.rawValue
    var date: Date = Date.now
    var odometer: Double = 0
    var provider: String = ""
    var amountStr: String = "0"
    var nextDate: Date? = nil
    var nextOdometer: Double? = nil
    var notes: String = ""
    @Attribute(.externalStorage) var receiptData: Data? = nil
    var vehicle: Vehicle? = nil

    init(title: String, category: MaintenanceCategory, date: Date, odometer: Double, provider: String,
         amount: Decimal, nextDate: Date?, nextOdometer: Double?, notes: String, vehicle: Vehicle?) {
        self.title = title; self.categoryRaw = category.rawValue; self.date = date
        self.odometer = odometer; self.provider = provider; self.amountStr = Money.str(amount)
        self.nextDate = nextDate; self.nextOdometer = nextOdometer; self.notes = notes; self.vehicle = vehicle
    }
    var category: MaintenanceCategory { MaintenanceCategory(rawValue: categoryRaw) ?? .other }
    var amount: Decimal { Money.dec(amountStr) }
}

@Model
final class MaintenanceSchedule {
    var id: UUID = UUID()
    var title: String = ""
    var categoryRaw: String = MaintenanceCategory.other.rawValue
    var dueDate: Date? = nil
    var dueOdometer: Double? = nil
    var isCompleted: Bool = false
    var reminderLeadDays: Int = 7
    var notificationsEnabled: Bool = true
    var notes: String = ""
    var createdAt: Date = Date.now
    var vehicle: Vehicle? = nil

    init(title: String, category: MaintenanceCategory, dueDate: Date?, dueOdometer: Double?,
         reminderLeadDays: Int, notes: String, vehicle: Vehicle?) {
        self.title = title; self.categoryRaw = category.rawValue; self.dueDate = dueDate
        self.dueOdometer = dueOdometer; self.reminderLeadDays = reminderLeadDays
        self.notes = notes; self.vehicle = vehicle
    }
    var category: MaintenanceCategory { MaintenanceCategory(rawValue: categoryRaw) ?? .other }
}

// MARK: - Documents & Reminders

@Model
final class VehicleDocument {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = DocumentType.other.rawValue
    var issueDate: Date? = nil
    var expiryDate: Date? = nil
    var notes: String = ""
    /// Stored in the app's private Documents directory reference name; file bytes in external storage attribute.
    @Attribute(.externalStorage) var fileData: Data? = nil
    var fileExtension: String = ""
    var createdAt: Date = Date.now
    var vehicle: Vehicle? = nil

    init(name: String, type: DocumentType, issueDate: Date?, expiryDate: Date?, notes: String, vehicle: Vehicle?) {
        self.name = name; self.typeRaw = type.rawValue; self.issueDate = issueDate
        self.expiryDate = expiryDate; self.notes = notes; self.vehicle = vehicle
    }
    var type: DocumentType { DocumentType(rawValue: typeRaw) ?? .other }
}

@Model
final class ReminderItem {
    var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = ReminderKind.custom.rawValue
    var date: Date? = nil
    var odometerTarget: Double? = nil
    var leadDays: Int = 7
    var isEnabled: Bool = true
    var vehicle: Vehicle? = nil

    init(title: String, kind: ReminderKind, date: Date?, odometerTarget: Double?, leadDays: Int, vehicle: Vehicle?) {
        self.title = title; self.kindRaw = kind.rawValue; self.date = date
        self.odometerTarget = odometerTarget; self.leadDays = leadDays; self.vehicle = vehicle
    }
    var kind: ReminderKind { ReminderKind(rawValue: kindRaw) ?? .custom }
}

// MARK: - Settings / entitlement (value types)

struct AppSettings: Codable, Equatable {
    var currencyCode: String = "USD"
    var distanceUnit: String = "km"          // km | mi
    var efficiencyUnit: String = "kmPerUnit" // kmPerUnit | per100 | mpg
    var appearance: String = "system"        // system | light | dark
    var firstWeekday: Int = 1                // 1 = Sunday … 7 = Saturday
    static let currencies = ["USD", "EUR", "GBP", "INR", "AUD", "CAD", "AED", "JPY"]
}

struct PurchaseEntitlement: Equatable {
    var isPro: Bool = false
    var productID: String? = nil
    var expirationDate: Date? = nil
}

/// Preferences stored in UserDefaults via @AppStorage (single source of truth for keys).
enum PrefKeys {
    static let currency = "currencyCode"
    static let distanceUnit = "distanceUnit"
    static let efficiencyUnit = "efficiencyUnit"
    static let appearance = "appearance"
    static let firstWeekday = "firstWeekday"
    static let selectedVehicleID = "selectedVehicleID"
    static let remindersEnabled = "remindersEnabled"
    static let maintenanceNotifications = "maintenanceNotifications"
    static let insuranceNotifications = "insuranceNotifications"
    static let registrationNotifications = "registrationNotifications"
    static let hasCompletedWelcome = "hasCompletedWelcome"
}

/// CONFIGURATION REQUIRED BEFORE APP STORE SUBMISSION (FIX 23):
/// The three values below are deliberate placeholders — NOT production
/// values and NOT invented real URLs. Replace them with the owner's real
/// support email and hosted privacy/terms pages (see README + docs/APP_STORE.md).
enum AppConfig {
    static let bundleID = "com.carcarelog.app"
    static let supportEmail = "salmanali929929@gmail.com" // CONFIGURATION REQUIRED: owner's real support email
    static let privacyURL = URL(string: "https://salmanalihere.github.io/carcare-log/privacy-policy.html") ?? URL(fileURLWithPath: "/") // CONFIGURATION REQUIRED: owner's hosted privacy policy
    static let termsURL = URL(string: "https://salmanalihere.github.io/carcare-log/terms-of-use.html") ?? URL(fileURLWithPath: "/") // CONFIGURATION REQUIRED: owner's hosted terms of use
}
