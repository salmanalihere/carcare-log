import SwiftUI
import SwiftData

struct MaintenanceView: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Environment(\.modelContext) private var context
    @AppStorage(PrefKeys.selectedVehicleID) private var selectedVehicleID = ""
    @AppStorage(PrefKeys.currency) private var currency = "USD"
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"
    @State private var segment = 0
    @State private var showAddRecord = false
    @State private var showAddSchedule = false

    private var vehicle: Vehicle? { VehicleSelection.resolve(vehicles: vehicles, selectedID: selectedVehicleID) }

    var body: some View {
        NavigationStack {
            Group {
                if let v = vehicle {
                    VStack(spacing: 0) {
                        Picker("Section", selection: $segment) {
                            Text("Schedules").tag(0)
                            Text("History").tag(1)
                        }
                        .pickerStyle(.segmented).padding()
                        if segment == 0 { schedules(v) } else { history(v) }
                    }
                } else {
                    EmptyStateView(icon: "wrench.and.screwdriver.fill", title: "No vehicle yet",
                                   message: "Add a vehicle first, then track its maintenance here.")
                }
            }
            .navigationTitle("Maintenance")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Log Service / Repair") { showAddRecord = true }
                        Button("Add Schedule / Reminder") { showAddSchedule = true }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddRecord) { if let v = vehicle { MaintenanceEditorView(record: nil, vehicle: v) } }
            .sheet(isPresented: $showAddSchedule) { if let v = vehicle { ScheduleEditorView(schedule: nil, vehicle: v) } }
        }
    }

    private func schedules(_ v: Vehicle) -> some View {
        List {
            let grouped: [(MaintenanceMath.Status, [MaintenanceSchedule])] = [.overdue, .dueSoon, .upcoming, .completed].map { st in
                (st, v.schedules.filter { MaintenanceMath.status(isCompleted: $0.isCompleted, dueDate: $0.dueDate, dueOdometer: $0.dueOdometer, currentOdometer: v.latestOdometer) == st }
                    .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) })
            }
            if v.schedules.isEmpty {
                Text("No maintenance schedules yet. Add one to get date and mileage reminders.").foregroundStyle(.secondary)
            }
            ForEach(grouped, id: \.0.rawValue) { group in
                if !group.1.isEmpty {
                    Section(group.0.label) {
                        ForEach(group.1) { s in
                            NavigationLink { ScheduleEditorView(schedule: s, vehicle: v) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.title).font(.headline)
                                        Text(detailText(s, v)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    StatusBadge(status: group.0)
                                }
                            }
                        }
                    }
                }
            }
            // Records that carry a next-service target act as schedules too.
            let withNext = v.maintenanceRecords.filter { $0.nextDate != nil || $0.nextOdometer != nil }
            if !withNext.isEmpty {
                Section("Next Service From Records") {
                    ForEach(withNext) { r in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.title).font(.headline)
                                Text([r.nextDate.map { "By " + $0.formatted(date: .abbreviated, time: .omitted) },
                                      r.nextOdometer.map { "By \(distText($0, distanceUnit))" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(status: MaintenanceMath.status(isCompleted: false, dueDate: r.nextDate, dueOdometer: r.nextOdometer, currentOdometer: v.latestOdometer))
                        }
                    }
                }
            }
        }
    }

    private func detailText(_ s: MaintenanceSchedule, _ v: Vehicle) -> String {
        var parts: [String] = [s.category.rawValue]
        if let d = s.dueDate, let days = MaintenanceMath.remainingDays(dueDate: d) { parts.append("\(days) days left") }
        if let km = MaintenanceMath.remainingKilometres(dueOdometer: s.dueOdometer, currentOdometer: v.latestOdometer) { parts.append("\(distText(km, distanceUnit)) left") }
        return parts.joined(separator: " · ")
    }

    private func history(_ v: Vehicle) -> some View {
        List {
            if v.maintenanceRecords.isEmpty {
                Text("No services or repairs logged yet.").foregroundStyle(.secondary)
            }
            ForEach(v.maintenanceRecords.sorted { $0.date > $1.date }) { r in
                NavigationLink { MaintenanceEditorView(record: r, vehicle: v) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(r.title).font(.headline); Spacer(); Text(currencyString(r.amountStr, code: currency)).bold() }
                        Text("\(r.category.rawValue) · \(r.date.formatted(date: .abbreviated, time: .omitted)) · \(distText(r.odometer, distanceUnit))\(r.provider.isEmpty ? "" : " · \(r.provider)")")
                            .font(.caption).foregroundStyle(.secondary)
                        if r.nextDate != nil || r.nextOdometer != nil {
                            Text("Next: \([r.nextDate.map { $0.formatted(date: .abbreviated, time: .omitted) }, r.nextOdometer.map { distText($0, distanceUnit) }].compactMap { $0 }.joined(separator: " / "))")
                                .font(.caption).foregroundStyle(Color.ccWarning)
                        }
                    }
                }
            }
        }
    }
}

struct MaintenanceEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var record: MaintenanceRecord?
    var vehicle: Vehicle

    @State private var title = ""
    @State private var category: MaintenanceCategory = .fullService
    @State private var date = Date.now
    @State private var odometer = ""
    @State private var provider = ""
    @State private var amount = ""
    @State private var hasNextDate = false; @State private var nextDate = Date.now
    @State private var hasNextOdo = false; @State private var nextOdo = ""
    @State private var notes = ""
    @State private var error: String? = nil
    @State private var confirmDelete = false
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"

    var body: some View {
        NavigationStack {
            Form {
                Section("Service / Repair") {
                    TextField("Title *", text: $title)
                    Picker("Category", selection: $category) { ForEach(MaintenanceCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    DatePicker("Service date", selection: $date)
                    TextField("Odometer (\(DistanceUnit.label(distanceUnit)))", text: $odometer).keyboardType(.decimalPad)
                    TextField("Service provider", text: $provider)
                    TextField("Amount paid", text: $amount).keyboardType(.decimalPad)
                }
                Section("Next Service") {
                    Toggle("Next service date", isOn: $hasNextDate)
                    if hasNextDate { DatePicker("Next date", selection: $nextDate, displayedComponents: .date) }
                    Toggle("Next service odometer", isOn: $hasNextOdo)
                    if hasNextOdo { TextField("Next odometer (\(DistanceUnit.label(distanceUnit)))", text: $nextOdo).keyboardType(.decimalPad) }
                }
                Section { TextField("Notes", text: $notes, axis: .vertical) }
                if let error { Text(error).foregroundStyle(Color.ccError) }
                if record != nil { Button("Delete Record", role: .destructive) { confirmDelete = true } }
            }
            .navigationTitle(record == nil ? "Log Service" : "Edit Record")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear(perform: load)
            .confirmationDialog("Delete this record?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let r = record { context.delete(r) }; dismiss() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func load() {
        if let r = record {
            title = r.title; category = r.category; date = r.date
            odometer = r.odometer > 0 ? String(format: "%.0f", DistanceUnit.displayValue(km: r.odometer, unit: distanceUnit)) : ""
            provider = r.provider; amount = r.amountStr == "0" ? "" : r.amountStr
            if let d = r.nextDate { hasNextDate = true; nextDate = d }
            if let o = r.nextOdometer { hasNextOdo = true; nextOdo = String(format: "%.0f", DistanceUnit.displayValue(km: o, unit: distanceUnit)) }
            notes = r.notes
        }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Title is required."; return }
        let odoDisplay = Double(odometer) ?? 0
        guard odoDisplay >= 0 else { error = "Odometer cannot be negative."; return }
        let odo = DistanceUnit.storedValue(display: odoDisplay, unit: distanceUnit) // display unit -> km
        let amt = Decimal(string: amount) ?? 0
        guard amt >= 0 else { error = "Amount cannot be negative."; return }
        let nextO: Double? = hasNextOdo ? Double(nextOdo).map { DistanceUnit.storedValue(display: $0, unit: distanceUnit) } : nil
        if let n = nextO, n <= odo { error = "Next service odometer must be higher than this service's odometer."; return }
        if hasNextDate && nextDate < date { error = "Next service date cannot be before the service date."; return }
        if let r = record {
            r.title = title; r.categoryRaw = category.rawValue; r.date = date; r.odometer = odo
            r.provider = provider; r.amountStr = Money.str(amt)
            r.nextDate = hasNextDate ? nextDate : nil; r.nextOdometer = nextO; r.notes = notes
        } else {
            context.insert(MaintenanceRecord(title: title, category: category, date: date, odometer: odo,
                                             provider: provider, amount: amt, nextDate: hasNextDate ? nextDate : nil,
                                             nextOdometer: nextO, notes: notes, vehicle: vehicle))
            MileageService.recordIfNeeded(vehicle: vehicle, odometer: odo, date: date, notes: "Service: \(title)", context: context)
        }
        dismiss()
    }
}

struct ScheduleEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrefKeys.remindersEnabled) private var remindersEnabled = false
    @AppStorage(PrefKeys.maintenanceNotifications) private var maintenanceNotifications = true
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"
    var schedule: MaintenanceSchedule?
    var vehicle: Vehicle

    @State private var title = ""
    @State private var category: MaintenanceCategory = .engineOil
    @State private var hasDate = true; @State private var dueDate = Date.now
    @State private var hasOdo = false; @State private var dueOdo = ""
    @State private var leadDays = 7
    @State private var notifications = true
    @State private var isCompleted = false
    @State private var notes = ""
    @State private var error: String? = nil
    @State private var confirmDelete = false
    private let leadOptions = [0, 7, 15, 30]

    var body: some View {
        NavigationStack {
            Form {
                Section("Schedule") {
                    TextField("Title * (e.g. Engine Oil)", text: $title)
                    Picker("Category", selection: $category) { ForEach(MaintenanceCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Toggle("Due date", isOn: $hasDate)
                    if hasDate { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
                    Toggle("Due odometer", isOn: $hasOdo)
                    if hasOdo { TextField("Due at (\(DistanceUnit.label(distanceUnit)))", text: $dueOdo).keyboardType(.decimalPad) }
                }
                Section("Reminder") {
                    Picker("Remind me", selection: $leadDays) {
                        Text("On the due date").tag(0); Text("7 days before").tag(7)
                        Text("15 days before").tag(15); Text("30 days before").tag(30)
                    }
                    Toggle("Notifications for this schedule", isOn: $notifications)
                    Text("Mileage-due status updates automatically as you log new odometer readings; notifications fire on the date reminder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if schedule != nil { Toggle("Completed", isOn: $isCompleted) }
                Section { TextField("Notes", text: $notes, axis: .vertical) }
                if let error { Text(error).foregroundStyle(Color.ccError) }
                if schedule != nil { Button("Delete Schedule", role: .destructive) { confirmDelete = true } }
            }
            .navigationTitle(schedule == nil ? "Add Schedule" : "Edit Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } } }
            }
            .onAppear(perform: load)
            .confirmationDialog("Delete this schedule?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let s = schedule { NotificationService.cancel(id: s.id); context.delete(s) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func load() {
        if let s = schedule {
            title = s.title; category = s.category; notes = s.notes
            leadDays = s.reminderLeadDays; notifications = s.notificationsEnabled; isCompleted = s.isCompleted
            if let d = s.dueDate { hasDate = true; dueDate = d } else { hasDate = false }
            if let o = s.dueOdometer { hasOdo = true; dueOdo = String(format: "%.0f", DistanceUnit.displayValue(km: o, unit: distanceUnit)) } else { hasOdo = false }
        }
    }

    private func save() async {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Title is required."; return }
        guard hasDate || hasOdo else { error = "Set at least a due date or a due odometer."; return }
        let dueO: Double? = hasOdo ? Double(dueOdo).map { DistanceUnit.storedValue(display: $0, unit: distanceUnit) } : nil
        if hasOdo && dueO == nil { error = "Enter a valid due odometer."; return }
        // Permission is requested here — when the user first configures a reminder — not at launch.
        if notifications && remindersEnabled && maintenanceNotifications {
            _ = await NotificationService.requestPermission()
        }
        let target: MaintenanceSchedule
        if let s = schedule { target = s } else {
            target = MaintenanceSchedule(title: title, category: category, dueDate: hasDate ? dueDate : nil,
                                         dueOdometer: dueO, reminderLeadDays: leadDays, notes: notes, vehicle: vehicle)
            context.insert(target)
        }
        target.title = title; target.categoryRaw = category.rawValue
        target.dueDate = hasDate ? dueDate : nil; target.dueOdometer = dueO
        target.reminderLeadDays = leadDays; target.notificationsEnabled = notifications
        target.isCompleted = isCompleted; target.notes = notes
        // Honours the per-schedule switch AND the global + category switches.
        if notifications && remindersEnabled && maintenanceNotifications && !isCompleted, let d = target.dueDate {
            NotificationService.schedule(id: target.id, title: "Maintenance due soon",
                                         body: "\(title) for \(vehicle.displayName) is coming up.",
                                         dueDate: d, leadDays: leadDays)
        } else {
            NotificationService.cancel(id: target.id)
        }
        dismiss()
    }
}
