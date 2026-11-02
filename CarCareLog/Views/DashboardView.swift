import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @AppStorage(PrefKeys.selectedVehicleID) private var selectedVehicleID = ""
    @AppStorage(PrefKeys.currency) private var currency = "USD"
    @AppStorage(PrefKeys.efficiencyUnit) private var efficiencyUnit = "kmPerUnit"
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"
    var goToVehicles: () -> Void = {}

    @State private var showFuel = false
    @State private var showExpense = false
    @State private var showService = false
    @State private var showMileage = false

    private var vehicle: Vehicle? { VehicleSelection.resolve(vehicles: vehicles, selectedID: selectedVehicleID) }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let v = vehicle {
                    VStack(spacing: 16) {
                        header(v)
                        cards(v)
                        quickActions(v)
                        NavigationLink { MileageHistoryView(vehicle: v) } label: {
                            Label("Mileage History", systemImage: "road.lanes")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(.ccAccent)
                        charts(v)
                        recentActivity(v)
                    }
                    .padding(16)
                } else {
                    EmptyStateView(icon: "car.fill", title: "No vehicle yet",
                                   message: "Add your first vehicle to start tracking fuel, expenses and maintenance.",
                                   actionTitle: "Add Vehicle", action: goToVehicles)
                        .padding(.top, 60)
                }
            }
            .background(Color.ccScreen)
            .navigationTitle("Dashboard")
            .sheet(isPresented: $showFuel) { if let v = vehicle { FuelEditorView(entry: nil, vehicle: v) } }
            .sheet(isPresented: $showExpense) { if let v = vehicle { ExpenseEditorView(expense: nil, vehicle: v) } }
            .sheet(isPresented: $showService) { if let v = vehicle { MaintenanceEditorView(record: nil, vehicle: v) } }
            .sheet(isPresented: $showMileage) { if let v = vehicle { MileageEntryView(vehicle: v) } }
        }
    }

    private func header(_ v: Vehicle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greeting).font(.title2.bold())
            Menu {
                ForEach(vehicles) { other in
                    Button(other.displayName) { selectedVehicleID = other.id.uuidString }
                }
            } label: {
                HStack {
                    if let data = v.photoData, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: v.vehicleType.icon).font(.title)
                            .frame(width: 54, height: 54)
                            .background(Color.ccAccent.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(Color.ccAccent)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text(v.displayName).font(.headline)
                            Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(v.registrationNumber.isEmpty ? "\(v.brand) \(v.model)" : v.registrationNumber)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cards(_ v: Vehicle) -> some View {
        // Centralized totals (FIX 12): ownership = fuel + expenses + maintenance.
        let monthTotals = FinancialCalculationService.totals(for: v) { Calendar.current.isDate($0, equalTo: .now, toGranularity: .month) }
        let thisMonth = monthTotals.ownership
        let monthly = FinancialCalculationService.monthlyTotals(for: v)
        let change: Double? = {
            guard monthly.count >= 2 else { return nil }
            let cur = NSDecimalNumber(decimal: monthly[monthly.count - 1].total).doubleValue
            let prev = NSDecimalNumber(decimal: monthly[monthly.count - 2].total).doubleValue
            guard prev > 0 else { return nil }
            return (cur - prev) / prev * 100.0
        }()
        let fuelMonth = monthTotals.fuel
        let fills = v.fuelEntries.map { FuelMath.Fill(odometer: $0.odometer, quantity: $0.quantity, isFullTank: $0.isFullTank, date: $0.date) }
        let efficiency = FuelMath.kmPerUnit(fills: fills)
        // Monthly distance comes from MileageEntry history only (FIX 7).
        let readings = v.mileageEntries.map { MileageMath.Reading(id: $0.id, date: $0.date, odometer: $0.odometer) }
        let distMonth = MileageMath.monthlyDistance(readings: readings)
        let next = v.schedules.filter { !$0.isCompleted }.min { (a, b) in (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture) }

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(title: "Total Expenses (Month)", value: currencyString(thisMonth, code: currency),
                     sub: change.map { String(format: "%@%.1f%% vs last month", $0 >= 0 ? "+" : "", $0) } ?? "No last-month data",
                     icon: "creditcard.fill", color: change != nil && (change ?? 0) > 0 ? .ccError : .ccAccent)
            statCard(title: "Fuel (Month)", value: currencyString(fuelMonth, code: currency),
                     sub: FuelMath.formattedEfficiency(kmPerUnit: efficiency, unit: efficiencyUnit, isElectric: v.fuelType.isElectric, distanceUnit: distanceUnit),
                     icon: "fuelpump.fill", color: .ccAccent)
            statCard(title: "Current Mileage", value: distText(v.latestOdometer, distanceUnit),
                     sub: distMonth.map { "\(distText($0, distanceUnit)) this month" } ?? "Monthly distance: not enough data",
                     icon: "gauge.with.dots.needle.67percent", color: .ccAccent)
            if let n = next {
                let status = MaintenanceMath.status(isCompleted: false, dueDate: n.dueDate, dueOdometer: n.dueOdometer, currentOdometer: v.latestOdometer)
                statCard(title: "Next Maintenance", value: n.title,
                         sub: [MaintenanceMath.remainingDays(dueDate: n.dueDate).map { "\($0) days left" },
                               MaintenanceMath.remainingKilometres(dueOdometer: n.dueOdometer, currentOdometer: v.latestOdometer).map { "\(distText($0, distanceUnit)) left" }]
                            .compactMap { $0 }.joined(separator: " · "),
                         icon: "wrench.and.screwdriver.fill", color: status.color)
            } else {
                statCard(title: "Next Maintenance", value: "None scheduled",
                         sub: "Add a schedule in Maintenance", icon: "wrench.and.screwdriver.fill", color: .ccGrey)
            }
        }
    }

    private func statCard(title: String, value: String, sub: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Image(systemName: icon).foregroundStyle(color); Text(title).font(.caption).foregroundStyle(.secondary) }
            Text(value).font(.headline).lineLimit(2)
            Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ccCard()
    }

    private func quickActions(_ v: Vehicle) -> some View {
        HStack(spacing: 10) {
            actionButton("Add Fuel", "fuelpump.fill") { showFuel = true }
            actionButton("Add Expense", "plus.circle.fill") { showExpense = true }
            actionButton("Log Service", "wrench.fill") { showService = true }
            actionButton("Add Mileage", "gauge.with.needle") { showMileage = true }
        }
    }

    private func actionButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .buttonStyle(.bordered).tint(.ccAccent)
    }

    private func charts(_ v: Vehicle) -> some View {
        let monthly = FinancialCalculationService.monthlyTotals(for: v)
        let breakdown = FinancialCalculationService.categoryTotals(for: v)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Monthly Expenses").font(.headline)
                if monthly.allSatisfy({ $0.total == 0 }) {
                    Text("No expenses recorded yet.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Chart(monthly, id: \.month) { item in
                        BarMark(x: .value("Month", item.month, unit: .month),
                                y: .value("Amount", NSDecimalNumber(decimal: item.total).doubleValue))
                        .foregroundStyle(Color.ccAccent)
                    }
                    .frame(height: 160)
                }
            }.ccCard()
            VStack(alignment: .leading, spacing: 8) {
                Text("Expense Breakdown").font(.headline)
                if breakdown.isEmpty {
                    Text("No data yet.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Chart(breakdown, id: \.category) { item in
                        SectorMark(angle: .value("Amount", NSDecimalNumber(decimal: item.total).doubleValue))
                            .foregroundStyle(by: .value("Category", item.category))
                    }
                    .frame(height: 180)
                }
            }.ccCard()
        }
    }

    private struct Activity: Identifiable {
        var id = UUID(); var icon: String; var title: String; var date: Date; var amount: String?
    }

    private func recentActivity(_ v: Vehicle) -> some View {
        var acts: [Activity] = []
        acts += v.fuelEntries.map { Activity(icon: "fuelpump.fill", title: "Fuel — \($0.station.isEmpty ? $0.fuelType.rawValue : $0.station)", date: $0.date, amount: currencyString($0.totalStr, code: currency)) }
        acts += v.expenses.map { Activity(icon: $0.category.icon, title: $0.title, date: $0.date, amount: currencyString($0.amountStr, code: currency)) }
        acts += v.maintenanceRecords.map { Activity(icon: "wrench.and.screwdriver.fill", title: $0.title, date: $0.date, amount: currencyString($0.amountStr, code: currency)) }
        let latest = Array(acts.sorted { $0.date > $1.date }.prefix(5))
        return VStack(alignment: .leading, spacing: 8) {
            Text("Recent Activity").font(.headline)
            if latest.isEmpty {
                Text("Nothing yet — use a quick action above to add your first record.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(latest) { a in
                    HStack {
                        Image(systemName: a.icon).foregroundStyle(Color.ccAccent).frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(a.title).font(.subheadline).lineLimit(1)
                            Text(a.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let amt = a.amount { Text(amt).font(.subheadline.bold()) }
                    }
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ccCard()
    }
}

/// Add / edit mileage: creates a persistent MileageEntry (FIX 3/4),
/// validated against its chronological neighbours (FIX 5) — historical
/// corrections are allowed when they keep the sequence consistent.
struct MileageEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"
    var vehicle: Vehicle
    var entry: MileageEntry? = nil
    @State private var date = Date.now
    @State private var reading = ""
    @State private var notes = ""
    @State private var error: String? = nil
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Mileage reading (\(DistanceUnit.label(distanceUnit)))") {
                    DatePicker("Date", selection: $date)
                    TextField("Odometer", text: $reading).keyboardType(.decimalPad)
                    TextField("Notes", text: $notes, axis: .vertical)
                    Text("Latest recorded: \(distText(vehicle.latestOdometer, distanceUnit)). Entries must fit the chronological sequence: previous \u{2264} this \u{2264} next.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(Color.ccError) }
                if entry != nil {
                    Button("Delete Entry", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(entry == nil ? "Add Mileage" : "Edit Mileage")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                if let e = entry {
                    date = e.date; notes = e.notes
                    reading = String(format: "%.0f", DistanceUnit.displayValue(km: e.odometer, unit: distanceUnit))
                }
            }
            .confirmationDialog("Delete this mileage entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let e = entry { context.delete(e) }; dismiss() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func save() {
        guard let display = Double(reading), display >= 0 else { error = "Enter a valid odometer reading."; return }
        let value = DistanceUnit.storedValue(display: display, unit: distanceUnit) // display unit -> stored km
        // Future dates are rejected with a clear message — never silently rewritten.
        guard date <= .now else { error = "Mileage date cannot be in the future."; return }
        let readings = vehicle.mileageEntries.map { MileageMath.Reading(id: $0.id, date: $0.date, odometer: $0.odometer) }
        guard !MileageMath.hasExactDuplicate(candidateDate: date, candidateOdometer: value, excludingID: entry?.id, in: readings) else {
            error = "An identical mileage entry already exists."; return
        }
        guard MileageMath.isValid(candidateDate: date, candidateOdometer: value, excludingID: entry?.id, in: readings) else {
            error = "This reading would break the chronological sequence. It must be \u{2265} the previous reading and \u{2264} the next reading for its date."
            return
        }
        if let e = entry {
            e.date = date; e.odometer = value; e.notes = notes
        } else {
            context.insert(MileageEntry(date: date, odometer: value, notes: notes, vehicle: vehicle))
        }
        // Vehicle's current odometer follows the chronologically latest entry.
        if let latest = vehicle.mileageEntries.sorted(by: { ($0.date, $0.odometer) < ($1.date, $1.odometer) }).last {
            vehicle.odometer = latest.odometer
        } else {
            vehicle.odometer = value
        }
        dismiss()
    }
}
