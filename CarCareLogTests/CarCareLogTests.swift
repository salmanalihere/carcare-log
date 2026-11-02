import XCTest
@testable import CarCareLog

final class CarCareLogTests: XCTestCase {
    private func fill(_ odo: Double, _ qty: Double, _ full: Bool, day: Int = 1) -> FuelMath.Fill {
        FuelMath.Fill(odometer: odo, quantity: qty, isFullTank: full,
                      date: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: day)) ?? .now)
    }

    // Fuel efficiency: full-tank method.
    func testFuelEfficiencyFullTankMethod() {
        // Full at 10,000 (40 L), partial 10 L at 10,300, full 30 L at 10,800.
        // Consumed after first full = 10 + 30 = 40 L over 800 km -> 20 km/L.
        let fills = [fill(10000, 40, true, day: 1), fill(10300, 10, false, day: 8), fill(10800, 30, true, day: 15)]
        XCTAssertEqual(FuelMath.kmPerUnit(fills: fills) ?? 0, 20.0, accuracy: 0.001)
        XCTAssertEqual(FuelMath.unitsPer100km(fills: fills) ?? 0, 5.0, accuracy: 0.001)
    }

    func testFuelEfficiencyInsufficientData() {
        XCTAssertNil(FuelMath.kmPerUnit(fills: [fill(10000, 40, true)]))
        XCTAssertNil(FuelMath.kmPerUnit(fills: [fill(10000, 40, false), fill(10500, 20, false)]))
        XCTAssertNil(FuelMath.kmPerUnit(fills: []))
    }

    func testFuelEfficiencyIgnoresZeroDistance() {
        XCTAssertNil(FuelMath.kmPerUnit(fills: [fill(10000, 40, true), fill(10000, 40, true)]))
    }

    func testCostPerKilometre() {
        let fills = [fill(10000, 40, true), fill(11000, 40, true)]
        XCTAssertEqual(FuelMath.costPerKilometre(fills: fills, totalCost: 100) ?? 0, 0.1, accuracy: 0.0001)
        XCTAssertNil(FuelMath.costPerKilometre(fills: [fill(10000, 40, true)], totalCost: 50))
    }

    // Expenses
    func testExpenseTotalsAndBreakdown() {
        let now = Date.now
        let items = [
            ExpenseMath.Item(amount: 100, date: now, category: "Fuel"),
            ExpenseMath.Item(amount: 50, date: now, category: "Repairs"),
            ExpenseMath.Item(amount: 25, date: now, category: "Fuel"),
        ]
        XCTAssertEqual(ExpenseMath.total(items), 175)
        XCTAssertEqual(ExpenseMath.total(inMonthContaining: now, items: items), 175)
        let breakdown = ExpenseMath.categoryBreakdown(items: items)
        XCTAssertEqual(breakdown.first?.category, "Fuel")
        XCTAssertEqual(breakdown.first?.total, 125)
    }

    func testMonthChangePercentNilWhenNoLastMonth() {
        let items = [ExpenseMath.Item(amount: 100, date: .now, category: "Fuel")]
        XCTAssertNil(ExpenseMath.monthChangePercent(items: items))
    }

    // Maintenance due logic
    func testMaintenanceOverdueByDate() {
        let past = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        XCTAssertEqual(MaintenanceMath.status(isCompleted: false, dueDate: past, dueOdometer: nil, currentOdometer: 1000), .overdue)
    }
    func testMaintenanceDueSoonByMileage() {
        XCTAssertEqual(MaintenanceMath.status(isCompleted: false, dueDate: nil, dueOdometer: 10500, currentOdometer: 10000), .dueSoon)
        XCTAssertEqual(MaintenanceMath.remainingKilometres(dueOdometer: 10500, currentOdometer: 10000), 500)
    }
    func testMaintenanceOverdueByMileageBeatsDueSoonByDate() {
        let soon = Calendar.current.date(byAdding: .day, value: 5, to: .now)
        XCTAssertEqual(MaintenanceMath.status(isCompleted: false, dueDate: soon, dueOdometer: 9000, currentOdometer: 10000), .overdue)
    }
    func testMaintenanceCompleted() {
        let past = Calendar.current.date(byAdding: .day, value: -10, to: .now)
        XCTAssertEqual(MaintenanceMath.status(isCompleted: true, dueDate: past, dueOdometer: 1, currentOdometer: 99999), .completed)
    }

    // Mileage validation
    func testMileageValidation() {
        XCTAssertTrue(MileageValidator.isValid(newReading: 10000, latestKnown: 10000))
        XCTAssertTrue(MileageValidator.isValid(newReading: 10001, latestKnown: 10000))
        XCTAssertFalse(MileageValidator.isValid(newReading: 9999, latestKnown: 10000))
        XCTAssertFalse(MileageValidator.isValid(newReading: -1, latestKnown: 0))
    }

    // Money: decimal exactness
    func testMoneyDecimalExactness() {
        XCTAssertEqual(Money.dec("0.1") + Money.dec("0.2"), Money.dec("0.3"))
        XCTAssertEqual(Money.str(Money.dec("19.99")), "19.99")
    }

    // CSV escaping
    func testCSVEscaping() {
        XCTAssertEqual(CSVExporter.escape("Shell, Main St"), "\"Shell, Main St\"")
        XCTAssertEqual(CSVExporter.escape("plain"), "plain")
        XCTAssertEqual(CSVExporter.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    // StoreKit configuration surface (IDs are the documented contract)
    func testProductIDs() {
        XCTAssertEqual(Set(StoreManager.productIDs),
                       ["com.carcarelog.monthly", "com.carcarelog.yearly", "com.carcarelog.lifetime"])
    }

    // Distance conversion (FIX 2): internal base unit is kilometres.
    func testDistanceConversionAccuracy() {
        XCTAssertEqual(DistanceUnit.displayValue(km: 100, unit: "mi"), 62.1371, accuracy: 0.001)
        XCTAssertEqual(DistanceUnit.displayValue(km: 100, unit: "km"), 100)
        XCTAssertEqual(DistanceUnit.storedValue(display: 62.1371, unit: "mi"), 100, accuracy: 0.001)
        // Round-trip in both units must be lossless.
        for unit in ["km", "mi"] {
            let km = 12345.6
            XCTAssertEqual(DistanceUnit.storedValue(display: DistanceUnit.displayValue(km: km, unit: unit), unit: unit), km, accuracy: 0.0001)
        }
        XCTAssertEqual(DistanceUnit.formatted(km: 160.9344, unit: "mi"), "100 mi")
        XCTAssertEqual(DistanceUnit.formatted(km: 500, unit: "km"), "500 km")
    }

    func testEfficiencyUnitConversions() {
        XCTAssertEqual(FuelMath.mpg(fromKmPerLitre: 10), 23.5215, accuracy: 0.001)
        XCTAssertEqual(FuelMath.kmPerLitre(fromMpg: FuelMath.mpg(fromKmPerLitre: 12.3)), 12.3, accuracy: 0.0001)
        XCTAssertEqual(FuelMath.formattedEfficiency(kmPerUnit: 10, unit: "kmPerUnit", isElectric: false), "10.00 km/L")
        XCTAssertEqual(FuelMath.formattedEfficiency(kmPerUnit: 10, unit: "per100", isElectric: false), "10.0 L/100 km")
        XCTAssertEqual(FuelMath.formattedEfficiency(kmPerUnit: 10, unit: "mpg", isElectric: false), "23.5 mpg")
        XCTAssertEqual(FuelMath.formattedEfficiency(kmPerUnit: 10, unit: "kmPerUnit", isElectric: false, distanceUnit: "mi"), "23.5 mpg")
        XCTAssertEqual(FuelMath.formattedEfficiency(kmPerUnit: 5, unit: "per100", isElectric: true), "20.0 kWh/100 km")
        XCTAssertEqual(FuelMath.formattedEfficiency(kmPerUnit: nil, unit: "mpg", isElectric: false), "Not enough data")
    }

    // Backup (FIX 1): complete round-trip at the current format version.
    func testBackupRoundTripPreservesEverything() throws {
        let v = Vehicle(name: "Daily", brand: "Toyota", model: "Corolla", year: 2021,
                        registrationNumber: "KA01AB1234", vehicleType: .sedan, fuelType: .petrol, odometer: 25000)
        v.photoData = Data([0x01, 0x02, 0x03])
        v.engineNumber = "ENG-9"; v.insuranceProvider = "Acme Insurance"
        v.insuranceExpiry = Date(timeIntervalSince1970: 1_800_000_000)
        v.registrationExpiry = Date(timeIntervalSince1970: 1_810_000_000)
        v.purchasePriceStr = "15000"; v.purchaseDate = Date(timeIntervalSince1970: 1_600_000_000)
        let fuel = FuelEntry(date: Date(timeIntervalSince1970: 1_700_000_000), odometer: 24000, fuelType: .petrol,
                             quantity: 35, pricePerUnit: Money.dec("1.50"), total: Money.dec("52.50"),
                             station: "Shell", isFullTank: true, notes: "trip", vehicle: v)
        fuel.receiptData = Data([0x09, 0x09])
        v.fuelEntries = [fuel]
        let exp = Expense(title: "Parking", category: .parking, amount: Money.dec("12"), date: .now,
                          odometer: 24500, provider: "CityPark", notes: "mall", vehicle: v)
        exp.receiptData = Data([0x07])
        v.expenses = [exp]
        let maint = MaintenanceRecord(title: "Oil change", category: .engineOil, date: .now, odometer: 24000,
                                      provider: "Dealer", amount: Money.dec("89"), nextDate: nil, nextOdometer: 29000,
                                      notes: "5W-30", vehicle: v)
        maint.receiptData = Data([0x05])
        v.maintenanceRecords = [maint]
        let sched = MaintenanceSchedule(title: "Engine Oil", category: .engineOil, dueDate: Date(timeIntervalSince1970: 1_900_000_000),
                                        dueOdometer: 30000, reminderLeadDays: 15, notes: "", vehicle: v)
        v.schedules = [sched]
        let rem = ReminderItem(title: "Check tyres", kind: .custom, date: Date(timeIntervalSince1970: 1_850_000_000),
                               odometerTarget: nil, leadDays: 7, vehicle: v)
        v.reminders = [rem]
        let doc = VehicleDocument(name: "Policy", type: .insurance, issueDate: Date(timeIntervalSince1970: 1_700_000_000),
                                  expiryDate: Date(timeIntervalSince1970: 1_800_000_000), notes: "", vehicle: v)
        doc.fileData = Data([0x0A, 0x0B]); doc.fileExtension = "jpg"
        v.documents = [doc]

        let data = try BackupService.makeBackup(vehicles: [v])
        let dto = try BackupService.decode(data)
        XCTAssertEqual(dto.effectiveVersion, 3)
        try BackupValidator.validate(dto)
        let restored = BackupService.buildVehicles(from: dto)
        XCTAssertEqual(restored.count, 1)
        let r = restored[0]
        XCTAssertEqual(r.id, v.id)
        XCTAssertEqual(r.photoData, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(r.insuranceProvider, "Acme Insurance")
        XCTAssertEqual(r.insuranceExpiry, v.insuranceExpiry)
        XCTAssertEqual(r.registrationExpiry, v.registrationExpiry)
        XCTAssertEqual(r.fuelEntries.first?.receiptData, Data([0x09, 0x09]))
        XCTAssertEqual(r.fuelEntries.first?.pricePerUnitStr, "1.5")
        XCTAssertEqual(r.expenses.first?.receiptData, Data([0x07]))
        XCTAssertEqual(r.expenses.first?.odometer, 24500)
        XCTAssertEqual(r.maintenanceRecords.first?.receiptData, Data([0x05]))
        XCTAssertEqual(r.maintenanceRecords.first?.nextOdometer, 29000)
        XCTAssertEqual(r.schedules.first?.reminderLeadDays, 15)
        XCTAssertEqual(r.schedules.first?.dueOdometer, 30000)
        XCTAssertEqual(r.reminders.first?.title, "Check tyres")
        XCTAssertEqual(r.documents.first?.fileData, Data([0x0A, 0x0B]))
        XCTAssertEqual(r.documents.first?.expiryDate, doc.expiryDate)
    }

    // Backup v1 files (no formatVersion, no photos/schedules/documents) still restore.
    func testBackupV1BackwardCompatibility() throws {
        let json = """
        {"exportedAt":"2026-01-01T00:00:00Z","vehicles":[{"name":"Old","brand":"Ford","model":"Focus","year":2018,
        "registrationNumber":"AB12","vehicleType":"Sedan","fuelType":"Petrol","odometer":50000,"vin":"","notes":"",
        "fuel":[],"expenses":[],"maintenance":[]}]}
        """
        let dto = try BackupService.decode(Data(json.utf8))
        XCTAssertEqual(dto.effectiveVersion, 1)
        try BackupValidator.validate(dto)
        let restored = BackupService.buildVehicles(from: dto)
        XCTAssertEqual(restored.first?.brand, "Ford")
        XCTAssertEqual(restored.first?.schedules.count, 0)
    }

    // Invalid backups are rejected during validation, before any insert.
    func testBackupValidationRejectsBadData() {
        let bad = BackupDTO(formatVersion: 2, exportedAt: .now, vehicles: [
            .init(name: "X", brand: "B", model: "M", year: 2020, registrationNumber: "", vehicleType: "Sedan",
                  fuelType: "Petrol", odometer: 100, vin: "", notes: "", fuel: [],
                  expenses: [.init(title: "Bad", category: "Other", amount: "-5", date: .now, provider: "")],
                  maintenance: [])
        ])
        XCTAssertThrowsError(try BackupValidator.validate(bad))
        let future = BackupDTO(formatVersion: 99, exportedAt: .now, vehicles: [])
        XCTAssertThrowsError(try BackupValidator.validate(future))
    }

    // MARK: - 1.0.2: MileageEntry chronological validation (FIX 5)
    private func reading(_ day: Int, _ odo: Double) -> MileageMath.Reading {
        MileageMath.Reading(id: UUID(), date: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: day)) ?? .now, odometer: odo)
    }
    func testHistoricalCorrectionAllowed() {
        let readings = [reading(1, 10000), reading(15, 10500), reading(30, 11000)]
        // Correcting 15 Jan from 10,500 to 10,400 keeps the sequence valid.
        XCTAssertTrue(MileageMath.isValid(candidateDate: reading(15, 0).date, candidateOdometer: 10400,
                                          excludingID: readings[1].id, in: readings))
        // 11,500 would exceed the next reading (11,000) and must be rejected.
        XCTAssertFalse(MileageMath.isValid(candidateDate: reading(15, 0).date, candidateOdometer: 11500,
                                           excludingID: readings[1].id, in: readings))
        // Below the previous reading (10,000) is also invalid.
        XCTAssertFalse(MileageMath.isValid(candidateDate: reading(15, 0).date, candidateOdometer: 9900,
                                           excludingID: readings[1].id, in: readings))
    }
    func testNewestAndOldestEdgeValidation() {
        let readings = [reading(1, 10000), reading(15, 10500)]
        XCTAssertTrue(MileageMath.isValid(candidateDate: reading(20, 0).date, candidateOdometer: 10600, in: readings))  // newest >= previous
        XCTAssertFalse(MileageMath.isValid(candidateDate: reading(20, 0).date, candidateOdometer: 10400, in: readings))
        XCTAssertTrue(MileageMath.isValid(candidateDate: Calendar.current.date(from: DateComponents(year: 2025, month: 12, day: 20)) ?? .now, candidateOdometer: 9000, in: readings)) // oldest <= next
        XCTAssertFalse(MileageMath.isValid(candidateDate: Calendar.current.date(from: DateComponents(year: 2025, month: 12, day: 20)) ?? .now, candidateOdometer: 10100, in: readings))
        XCTAssertFalse(MileageMath.isValid(candidateDate: reading(20, 0).date, candidateOdometer: -5, in: readings))
    }
    func testFutureDatedMileageRejected() {
        let readings = [reading(1, 10000)]
        let future = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        XCTAssertFalse(MileageMath.isValid(candidateDate: future, candidateOdometer: 10100, in: readings))
        XCTAssertTrue(MileageMath.isValid(candidateDate: .now, candidateOdometer: 10100, in: readings))
    }
    func testExactDuplicateMileageDetection() {
        let existing = reading(10, 10200)
        let readings = [reading(1, 10000), existing]
        // Same date/time + same odometer = duplicate (for a different entry).
        XCTAssertTrue(MileageMath.hasExactDuplicate(candidateDate: existing.date, candidateOdometer: 10200, excludingID: UUID(), in: readings))
        // Editing the entry itself is not a duplicate of itself.
        XCTAssertFalse(MileageMath.hasExactDuplicate(candidateDate: existing.date, candidateOdometer: 10200, excludingID: existing.id, in: readings))
        // Different odometer or different date is a legitimate entry, not a duplicate.
        XCTAssertFalse(MileageMath.hasExactDuplicate(candidateDate: existing.date, candidateOdometer: 10250, in: readings))
        XCTAssertFalse(MileageMath.hasExactDuplicate(candidateDate: reading(11, 0).date, candidateOdometer: 10200, in: readings))
    }
    func testMonthlyDistanceFromMileageHistory() {
        let cal = Calendar.current
        func r(_ y: Int, _ m: Int, _ d: Int, _ o: Double) -> MileageMath.Reading {
            MileageMath.Reading(id: UUID(), date: cal.date(from: DateComponents(year: y, month: m, day: d)) ?? .now, odometer: o)
        }
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15)) ?? .now
        // Baseline 31 May 10,000; latest in June 10,800 -> 800.
        XCTAssertEqual(MileageMath.monthlyDistance(readings: [r(2026, 5, 31, 10000), r(2026, 6, 10, 10800)], containing: now) ?? -1, 800, accuracy: 0.001)
        // Single reading, no baseline -> nil (never misleading).
        XCTAssertNil(MileageMath.monthlyDistance(readings: [r(2026, 6, 10, 10800)], containing: now))
        // No readings in the month -> nil.
        XCTAssertNil(MileageMath.monthlyDistance(readings: [r(2026, 5, 31, 10000)], containing: now))
    }

    // MARK: - 1.0.2: Centralized financial totals (FIX 11/15)
    private func makeVehicle(fuel: Decimal, expense: Decimal, maintenance: Decimal) -> Vehicle {
        let v = Vehicle(name: "T", brand: "B", model: "M", year: 2022, registrationNumber: "R",
                        vehicleType: .sedan, fuelType: .petrol, odometer: 10000)
        if fuel > 0 { v.fuelEntries = [FuelEntry(date: .now, odometer: 9000, fuelType: .petrol, quantity: 10, pricePerUnit: 1, total: fuel, station: "", isFullTank: true, notes: "", vehicle: v)] }
        if expense > 0 { v.expenses = [Expense(title: "E", category: .parking, amount: expense, date: .now, odometer: 0, provider: "", notes: "", vehicle: v)] }
        if maintenance > 0 { v.maintenanceRecords = [MaintenanceRecord(title: "Oil", category: .engineOil, date: .now, odometer: 9000, provider: "", amount: maintenance, nextDate: nil, nextOdometer: nil, notes: "", vehicle: v)] }
        return v
    }
    func testFinancialTotalsAllCombinations() {
        XCTAssertEqual(FinancialCalculationService.totals(for: makeVehicle(fuel: 100, expense: 0, maintenance: 0)).ownership, 100)
        XCTAssertEqual(FinancialCalculationService.totals(for: makeVehicle(fuel: 0, expense: 50, maintenance: 0)).ownership, 50)
        XCTAssertEqual(FinancialCalculationService.totals(for: makeVehicle(fuel: 0, expense: 0, maintenance: 70)).ownership, 70)
        XCTAssertEqual(FinancialCalculationService.totals(for: makeVehicle(fuel: 100, expense: 50, maintenance: 0)).ownership, 150)
        XCTAssertEqual(FinancialCalculationService.totals(for: makeVehicle(fuel: 100, expense: 0, maintenance: 70)).ownership, 170)
        XCTAssertEqual(FinancialCalculationService.totals(for: makeVehicle(fuel: 0, expense: 50, maintenance: 70)).ownership, 120)
        let all = FinancialCalculationService.totals(for: makeVehicle(fuel: 100, expense: 50, maintenance: 70))
        XCTAssertEqual(all.ownership, 220)
        XCTAssertEqual(all.fuel + all.expenses + all.maintenance, all.ownership)
        XCTAssertEqual(FinancialCalculationService.totals(for: makeVehicle(fuel: 0, expense: 0, maintenance: 0)).ownership, 0)
        // Vehicle.totalExpenses uses the same centralized definition.
        XCTAssertEqual(makeVehicle(fuel: 100, expense: 50, maintenance: 70).totalExpenses, 220)
    }
    func testFinancialDecimalAccuracy() {
        let t = FinancialCalculationService.totals(for: makeVehicle(fuel: Money.dec("0.1"), expense: Money.dec("0.2"), maintenance: Money.dec("0.3")))
        XCTAssertEqual(t.ownership, Money.dec("0.6"))
    }

    // MARK: - 1.0.2: Report dataset filtering + CSV (FIX 9/13/14/15)
    func testReportDatasetFilteringAndCSV() {
        let cal = Calendar.current
        let v = makeVehicle(fuel: 100, expense: 50, maintenance: 70)
        // Backdate the maintenance record to last year.
        let old = cal.date(byAdding: .year, value: -1, to: .now) ?? .now
        v.maintenanceRecords[0].date = old
        let all = ReportDataset.make(vehicle: v, periodLabel: "All Records", range: nil)
        XCTAssertEqual(all.totals.ownership, 220)
        XCTAssertEqual(all.maintenance.count, 1)
        let month = ReportDataset.make(vehicle: v, periodLabel: "This Month", range: cal.dateInterval(of: .month, for: .now))
        XCTAssertEqual(month.maintenance.count, 0)
        XCTAssertEqual(month.totals.ownership, 150)
        let csv = CSVExporter.reportCSV(dataset: all)
        XCTAssertTrue(csv.contains("Maintenance"))
        XCTAssertTrue(csv.contains("Oil"))
        XCTAssertTrue(csv.contains("Total ownership cost"))
        XCTAssertTrue(csv.contains("220"))
        let monthCSV = CSVExporter.reportCSV(dataset: month)
        XCTAssertFalse(monthCSV.contains("Oil"))
    }
    func testPDFDataGeneratedFromDataset() {
        let v = makeVehicle(fuel: 100, expense: 50, maintenance: 70)
        let dataset = ReportDataset.make(vehicle: v, periodLabel: "All Records", range: nil)
        let data = PDFReportService.makeReport(vehicle: v, dataset: dataset, currency: "USD")
        XCTAssertTrue(data.count > 500)
        XCTAssertEqual(dataset.totals.ownership, 220) // the totals the PDF prints
    }

    // MARK: - 1.0.2: Backup v3 mileage + identifiers (FIX 16/17/18)
    func testBackupV3IncludesMileage() throws {
        let v = makeVehicle(fuel: 0, expense: 0, maintenance: 0)
        v.mileageEntries = [MileageEntry(date: Date(timeIntervalSince1970: 1_700_000_000), odometer: 9500, notes: "check", vehicle: v)]
        let dto = try BackupService.decode(try BackupService.makeBackup(vehicles: [v]))
        XCTAssertEqual(dto.effectiveVersion, 3)
        try BackupValidator.validate(dto)
        let restored = BackupService.buildVehicles(from: dto)
        XCTAssertEqual(restored.first?.mileageEntries.count, 1)
        XCTAssertEqual(restored.first?.mileageEntries.first?.odometer, 9500)
        XCTAssertEqual(restored.first?.mileageEntries.first?.vehicle?.id, v.id)
        XCTAssertEqual(restored.first?.latestOdometer, 9500)
    }
    func testNotificationIdentifiersAreNamespacedAndUnique() {
        let id = UUID()
        XCTAssertEqual(NotificationService.maintenanceIdentifier(id), "cc-maintenance-\(id.uuidString)")
        XCTAssertEqual(NotificationService.insuranceIdentifier(id), "cc-insurance-\(id.uuidString)")
        XCTAssertEqual(NotificationService.registrationIdentifier(id), "cc-registration-\(id.uuidString)")
        XCTAssertEqual(NotificationService.documentIdentifier(id), "cc-document-\(id.uuidString)")
        XCTAssertEqual(NotificationService.reminderIdentifier(id), "cc-reminder-\(id.uuidString)")
        let all = [NotificationService.maintenanceIdentifier(id), NotificationService.insuranceIdentifier(id),
                   NotificationService.registrationIdentifier(id), NotificationService.documentIdentifier(id),
                   NotificationService.reminderIdentifier(id)]
        XCTAssertEqual(Set(all).count, 5)
    }
    func testEntitlementDefaultsToNotPro() {
        // No fake local unlock: a fresh entitlement value is never Pro.
        XCTAssertFalse(PurchaseEntitlement().isPro)
    }

    // Free-plan gate logic (entitlement itself is verified live by StoreKit in StoreManager)
    @MainActor func testFreeVehicleGate() {
        let manager = StoreManager()
        XCTAssertTrue(manager.canAddVehicle(currentCount: 0))
        XCTAssertFalse(manager.canAddVehicle(currentCount: 1))
    }
}
