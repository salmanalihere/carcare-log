import SwiftUI
import SwiftData
import PhotosUI

struct VehiclesView: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @EnvironmentObject private var store: StoreManager
    @AppStorage(PrefKeys.currency) private var currency = "USD"
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"
    @State private var showAdd = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if vehicles.isEmpty {
                    EmptyStateView(icon: "car.2.fill", title: "No vehicles",
                                   message: "Add a vehicle to start tracking. The free plan includes one vehicle.",
                                   actionTitle: "Add Vehicle", action: { showAdd = true })
                } else {
                    List(vehicles) { v in
                        NavigationLink { VehicleDetailView(vehicle: v) } label: {
                            HStack(spacing: 12) {
                                vehicleThumb(v)
                                VStack(alignment: .leading) {
                                    Text(v.displayName).font(.headline)
                                    Text("\(v.brand) \(v.model) · \(v.year)").font(.subheadline).foregroundStyle(.secondary)
                                    Text("\(distText(v.latestOdometer, distanceUnit)) · \(currencyString(v.totalExpenses, code: currency)) total")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Vehicles")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { addTapped() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Vehicle")
                }
            }
            .sheet(isPresented: $showAdd) { VehicleEditorView(vehicle: nil) }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private func addTapped() {
        if store.canAddVehicle(currentCount: vehicles.count) { showAdd = true } else { showPaywall = true }
    }

    @ViewBuilder func vehicleThumb(_ v: Vehicle) -> some View {
        if let data = v.photoData, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill().frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Image(systemName: v.vehicleType.icon).foregroundStyle(Color.ccAccent)
                .frame(width: 48, height: 48).background(Color.ccAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct VehicleDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrefKeys.currency) private var currency = "USD"
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"
    @AppStorage(PrefKeys.remindersEnabled) private var remindersEnabled = false
    @AppStorage(PrefKeys.maintenanceNotifications) private var maintenanceNotifications = true
    @AppStorage(PrefKeys.insuranceNotifications) private var insuranceNotifications = true
    @AppStorage(PrefKeys.registrationNotifications) private var registrationNotifications = true
    @AppStorage(PrefKeys.selectedVehicleID) private var selectedVehicleID = ""
    var vehicle: Vehicle
    @State private var showEdit = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    if let data = vehicle.photoData, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: vehicle.vehicleType.icon).font(.system(size: 44)).foregroundStyle(Color.ccAccent)
                    }
                    Text(vehicle.displayName).font(.title3.bold())
                    Text(vehicle.registrationNumber).foregroundStyle(.secondary)
                    Button("Use as Selected Vehicle") { selectedVehicleID = vehicle.id.uuidString }
                        .buttonStyle(.bordered).tint(.ccAccent)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section("Overview") {
                LabeledContent("Current mileage", value: distText(vehicle.latestOdometer, distanceUnit))
                LabeledContent("Total ownership expenses", value: currencyString(vehicle.totalExpenses, code: currency))
                LabeledContent("Total fuel expenses", value: currencyString(vehicle.totalFuelExpenses, code: currency))
                LabeledContent("Total maintenance", value: currencyString(vehicle.totalMaintenanceExpenses, code: currency))
                if let d = vehicle.purchaseDate { LabeledContent("Purchased", value: d.formatted(date: .abbreviated, time: .omitted)) }
                if Money.dec(vehicle.purchasePriceStr) > 0 { LabeledContent("Purchase price", value: currencyString(vehicle.purchasePriceStr, code: currency)) }
                if !vehicle.vin.isEmpty { LabeledContent("VIN", value: vehicle.vin) }
            }
            Section("Upcoming Reminders") {
                let upcoming = vehicle.schedules.filter { !$0.isCompleted }
                if upcoming.isEmpty { Text("No upcoming reminders.").foregroundStyle(.secondary) }
                ForEach(upcoming) { s in
                    HStack {
                        Text(s.title)
                        Spacer()
                        StatusBadge(status: MaintenanceMath.status(isCompleted: false, dueDate: s.dueDate, dueOdometer: s.dueOdometer, currentOdometer: vehicle.latestOdometer))
                    }
                }
                if let d = vehicle.insuranceExpiry { LabeledContent("Insurance expires", value: d.formatted(date: .abbreviated, time: .omitted)) }
                if let d = vehicle.registrationExpiry { LabeledContent("Registration expires", value: d.formatted(date: .abbreviated, time: .omitted)) }
            }
            Section {
                NavigationLink("Mileage History") { MileageHistoryView(vehicle: vehicle) }
                NavigationLink("Documents") { DocumentsView(vehicle: vehicle) }
                NavigationLink("Service History") { ServiceHistoryView(vehicle: vehicle) }
            }
            Section {
                Button("Edit Vehicle") { showEdit = true }
                Button("Delete Vehicle", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(vehicle.displayName)
        .sheet(isPresented: $showEdit) { VehicleEditorView(vehicle: vehicle) }
        .confirmationDialog("Delete this vehicle and all its records?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Vehicle and Records", role: .destructive) {
                for s in vehicle.schedules { NotificationService.cancel(id: s.id) }
                NotificationService.cancelInsurance(vehicleID: vehicle.id)
                NotificationService.cancelRegistration(vehicleID: vehicle.id)
                for d in vehicle.documents { NotificationService.cancelDocument(id: d.id) }
                for r in vehicle.reminders { NotificationService.cancelReminder(id: r.id) }
                context.delete(vehicle)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Fuel, expenses, maintenance, schedules and documents for this vehicle will be permanently removed.")
        }
    }
}

struct ServiceHistoryView: View {
    var vehicle: Vehicle
    @AppStorage(PrefKeys.currency) private var currency = "USD"
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"
    var body: some View {
        List {
            if vehicle.maintenanceRecords.isEmpty {
                Text("No service records yet.").foregroundStyle(.secondary)
            }
            ForEach(vehicle.maintenanceRecords.sorted { $0.date > $1.date }) { r in
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.title).font(.headline)
                    Text("\(r.category.rawValue) · \(r.date.formatted(date: .abbreviated, time: .omitted)) · \(distText(r.odometer, distanceUnit))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(currencyString(r.amountStr, code: currency)).font(.subheadline.bold())
                }
            }
        }
        .navigationTitle("Service History")
    }
}

struct VehicleEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var vehicle: Vehicle?

    @State private var name = ""
    @State private var brand = ""
    @State private var model = ""
    @State private var year = "2022"
    @State private var registration = ""
    @State private var vehicleType: VehicleType = .sedan
    @State private var fuelType: FuelType = .petrol
    @State private var odometer = ""
    @State private var vin = ""
    @State private var engineNumber = ""
    @State private var hasPurchaseDate = false
    @State private var purchaseDate = Date.now
    @State private var purchasePrice = ""
    @State private var insuranceProvider = ""
    @State private var hasInsuranceExpiry = false
    @State private var insuranceExpiry = Date.now
    @State private var hasRegistrationExpiry = false
    @State private var registrationExpiry = Date.now
    @State private var notes = ""
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var photoData: Data? = nil
    @State private var error: String? = nil
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"
    @AppStorage(PrefKeys.remindersEnabled) private var editRemindersEnabled = false
    @AppStorage(PrefKeys.maintenanceNotifications) private var editMaintenanceNotifications = true
    @AppStorage(PrefKeys.insuranceNotifications) private var editInsuranceNotifications = true
    @AppStorage(PrefKeys.registrationNotifications) private var editRegistrationNotifications = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    TextField("Vehicle name *", text: $name)
                    TextField("Brand / manufacturer *", text: $brand)
                    TextField("Model *", text: $model)
                    TextField("Manufacturing year *", text: $year).keyboardType(.numberPad)
                    TextField("Registration number *", text: $registration)
                    Picker("Vehicle type", selection: $vehicleType) { ForEach(VehicleType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Picker("Fuel type", selection: $fuelType) { ForEach(FuelType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    TextField("Current odometer (\(DistanceUnit.label(distanceUnit))) *", text: $odometer).keyboardType(.decimalPad)
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("Vehicle Photo", systemImage: "photo") }
                    if let data = photoData, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 140)
                    }
                }
                Section("Optional Details") {
                    TextField("VIN / chassis number", text: $vin)
                    TextField("Engine number", text: $engineNumber)
                    Toggle("Purchase date", isOn: $hasPurchaseDate)
                    if hasPurchaseDate { DatePicker("Purchased", selection: $purchaseDate, displayedComponents: .date) }
                    TextField("Purchase price", text: $purchasePrice).keyboardType(.decimalPad)
                    TextField("Insurance provider", text: $insuranceProvider)
                    Toggle("Insurance expiry", isOn: $hasInsuranceExpiry)
                    if hasInsuranceExpiry { DatePicker("Insurance expires", selection: $insuranceExpiry, displayedComponents: .date) }
                    Toggle("Registration expiry", isOn: $hasRegistrationExpiry)
                    if hasRegistrationExpiry { DatePicker("Registration expires", selection: $registrationExpiry, displayedComponents: .date) }
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                if let error { Text(error).foregroundStyle(Color.ccError) }
            }
            .navigationTitle(vehicle == nil ? "Add Vehicle" : "Edit Vehicle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, item in
                Task { if let data = try? await item?.loadTransferable(type: Data.self) { photoData = data } }
            }
        }
    }

    private func load() {
        guard let v = vehicle else { return }
        name = v.name; brand = v.brand; model = v.model; year = String(v.year)
        registration = v.registrationNumber; vehicleType = v.vehicleType; fuelType = v.fuelType
        odometer = String(format: "%.0f", DistanceUnit.displayValue(km: v.odometer, unit: distanceUnit)); vin = v.vin; engineNumber = v.engineNumber
        if let d = v.purchaseDate { hasPurchaseDate = true; purchaseDate = d }
        purchasePrice = v.purchasePriceStr == "0" ? "" : v.purchasePriceStr
        insuranceProvider = v.insuranceProvider
        if let d = v.insuranceExpiry { hasInsuranceExpiry = true; insuranceExpiry = d }
        if let d = v.registrationExpiry { hasRegistrationExpiry = true; registrationExpiry = d }
        notes = v.notes; photoData = v.photoData
    }

    private func save() {
        guard !brand.trimmingCharacters(in: .whitespaces).isEmpty, !model.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Brand and model are required."; return
        }
        guard let y = Int(year), (1950...2100).contains(y) else { error = "Enter a valid manufacturing year."; return }
        guard let odoDisplay = Double(odometer), odoDisplay >= 0 else { error = "Enter a valid, non-negative odometer reading."; return }
        let odo = DistanceUnit.storedValue(display: odoDisplay, unit: distanceUnit) // display unit -> km
        if let v = vehicle, !MileageValidator.isValid(newReading: odo, latestKnown: v.latestOdometer) {
            error = "Odometer cannot be lower than the latest recorded reading (\(distText(v.latestOdometer, distanceUnit)))."; return
        }
        let target: Vehicle
        if let v = vehicle { target = v } else {
            target = Vehicle(name: name, brand: brand, model: model, year: y, registrationNumber: registration,
                             vehicleType: vehicleType, fuelType: fuelType, odometer: odo)
            context.insert(target)
        }
        target.name = name; target.brand = brand; target.model = model; target.year = y
        target.registrationNumber = registration; target.vehicleTypeRaw = vehicleType.rawValue
        target.fuelTypeRaw = fuelType.rawValue; target.odometer = odo
        target.vin = vin; target.engineNumber = engineNumber
        target.purchaseDate = hasPurchaseDate ? purchaseDate : nil
        target.purchasePriceStr = Money.str(Money.dec(purchasePrice))
        target.insuranceProvider = insuranceProvider
        target.insuranceExpiry = hasInsuranceExpiry ? insuranceExpiry : nil
        target.registrationExpiry = hasRegistrationExpiry ? registrationExpiry : nil
        target.notes = notes; target.photoData = photoData
        // A brand-new vehicle starts its mileage history with its first reading (FIX 6).
        if vehicle == nil && odo > 0 && target.mileageEntries.isEmpty {
            context.insert(MileageEntry(date: .now, odometer: odo, notes: "Initial reading", vehicle: target))
        }
        // Insurance / registration expiry may have changed: re-arm notifications.
        NotificationService.reschedule(vehicle: target, globalEnabled: editRemindersEnabled,
                                       maintenanceEnabled: editMaintenanceNotifications,
                                       insuranceEnabled: editInsuranceNotifications,
                                       registrationEnabled: editRegistrationNotifications)
        dismiss()
    }
}

/// Dedicated mileage history from persisted MileageEntry records (FIX 4).
struct MileageHistoryView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"
    var vehicle: Vehicle
    @State private var showAdd = false
    @State private var editing: MileageEntry? = nil

    private var entries: [MileageEntry] {
        vehicle.mileageEntries.sorted { ($0.date, $0.odometer) > ($1.date, $1.odometer) }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Vehicle", value: vehicle.displayName)
                LabeledContent("Current mileage", value: distText(vehicle.latestOdometer, distanceUnit))
                if let d = MileageMath.monthlyDistance(readings: vehicle.mileageEntries.map { .init(id: $0.id, date: $0.date, odometer: $0.odometer) }) {
                    LabeledContent("Distance this month", value: distText(d, distanceUnit))
                } else {
                    LabeledContent("Distance this month", value: "Not enough data")
                }
            }
            if entries.isEmpty {
                Text("No mileage entries yet. Add one to start the history.").foregroundStyle(.secondary)
            }
            ForEach(entries) { e in
                Button { editing = e } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(distText(e.odometer, distanceUnit)).font(.headline).foregroundStyle(.primary)
                            Text(e.date, style: .date).font(.caption).foregroundStyle(.secondary)
                            if !e.notes.isEmpty { Text(e.notes).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { context.delete(e) }
                }
            }
        }
        .navigationTitle("Mileage History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add Mileage")
            }
        }
        .sheet(isPresented: $showAdd) { MileageEntryView(vehicle: vehicle) }
        .sheet(item: $editing) { e in MileageEntryView(vehicle: vehicle, entry: e) }
    }
}

// MARK: - Documents (Pro)

struct DocumentsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: StoreManager
    var vehicle: Vehicle
    @State private var showAdd = false
    @State private var showPaywall = false

    var body: some View {
        List {
            if !store.isPro {
                Section {
                    Text("Document management is a CarCare Log Pro feature.")
                    Button("View Pro") { showPaywall = true }
                }
            }
            ForEach(vehicle.documents.sorted { $0.createdAt > $1.createdAt }) { doc in
                VStack(alignment: .leading, spacing: 3) {
                    Text(doc.name).font(.headline)
                    Text(doc.type.rawValue).font(.caption).foregroundStyle(.secondary)
                    if let d = doc.expiryDate {
                        Text("Expires \(d.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(d < .now ? Color.ccError : Color.ccWarning)
                    }
                    if doc.fileData != nil { Text("Attachment saved securely on this device").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            .onDelete { idx in
                for i in idx { let d = vehicle.documents.sorted { $0.createdAt > $1.createdAt }[i]; NotificationService.cancelDocument(id: d.id); context.delete(d) }
            }
        }
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.isPro ? (showAdd = true) : (showPaywall = true) } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { DocumentEditorView(vehicle: vehicle) }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }
}

struct DocumentEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var vehicle: Vehicle
    @State private var name = ""
    @State private var type: DocumentType = .insurance
    @State private var hasIssue = false; @State private var issue = Date.now
    @State private var hasExpiry = false; @State private var expiry = Date.now
    @State private var notes = ""
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var fileData: Data? = nil
    @State private var error: String? = nil
    @AppStorage(PrefKeys.remindersEnabled) private var docRemindersEnabled = false
    @AppStorage(PrefKeys.maintenanceNotifications) private var docMaintenanceNotifications = true
    @AppStorage(PrefKeys.insuranceNotifications) private var docInsuranceNotifications = true
    @AppStorage(PrefKeys.registrationNotifications) private var docRegistrationNotifications = true

    var body: some View {
        NavigationStack {
            Form {
                TextField("Document name *", text: $name)
                Picker("Type", selection: $type) { ForEach(DocumentType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Toggle("Issue date", isOn: $hasIssue)
                if hasIssue { DatePicker("Issued", selection: $issue, displayedComponents: .date) }
                Toggle("Expiry date", isOn: $hasExpiry)
                if hasExpiry { DatePicker("Expires", selection: $expiry, displayedComponents: .date) }
                PhotosPicker(selection: $photoItem, matching: .images) { Label("Attach Image", systemImage: "paperclip") }
                if fileData != nil { Text("Image attached").font(.caption).foregroundStyle(.secondary) }
                TextField("Notes", text: $notes, axis: .vertical)
                if let error { Text(error).foregroundStyle(Color.ccError) }
            }
            .navigationTitle("Add Document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onChange(of: photoItem) { _, item in
                Task { if let data = try? await item?.loadTransferable(type: Data.self) { fileData = data } }
            }
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Document name is required."; return }
        if hasIssue && hasExpiry && expiry < issue { error = "Expiry cannot be before the issue date."; return }
        let doc = VehicleDocument(name: name, type: type, issueDate: hasIssue ? issue : nil,
                                  expiryDate: hasExpiry ? expiry : nil, notes: notes, vehicle: vehicle)
        doc.fileData = fileData
        doc.fileExtension = fileData == nil ? "" : "jpg"
        context.insert(doc)
        NotificationService.reschedule(vehicle: vehicle, globalEnabled: docRemindersEnabled,
                                       maintenanceEnabled: docMaintenanceNotifications,
                                       insuranceEnabled: docInsuranceNotifications,
                                       registrationEnabled: docRegistrationNotifications)
        dismiss()
    }
}
