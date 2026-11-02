import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Query private var vehicles: [Vehicle]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: StoreManager

    @AppStorage(PrefKeys.currency) private var currency = "USD"
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"
    @AppStorage(PrefKeys.efficiencyUnit) private var efficiencyUnit = "kmPerUnit"
    @AppStorage(PrefKeys.appearance) private var appearance = "system"
    @AppStorage(PrefKeys.firstWeekday) private var firstWeekday = 1
    @AppStorage(PrefKeys.remindersEnabled) private var remindersEnabled = false
    @AppStorage(PrefKeys.maintenanceNotifications) private var maintenanceNotifications = true
    @AppStorage(PrefKeys.insuranceNotifications) private var insuranceNotifications = true
    @AppStorage(PrefKeys.registrationNotifications) private var registrationNotifications = true

    @State private var showPaywall = false
    @State private var showImporter = false
    @State private var importMode: String = "merge"   // "merge" | "replace"
    @State private var confirmRestore = false
    @State private var confirmClear = false
    @State private var message: String? = nil
    @State private var shareItems: [Any]? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Premium") {
                    if store.isPro {
                        Label("CarCare Log Pro is active", systemImage: "checkmark.seal.fill").foregroundStyle(Color.ccAccent)
                        if let id = store.entitlement.productID { Text(id).font(.caption).foregroundStyle(.secondary) }
                    } else {
                        Button { showPaywall = true } label: {
                            HStack {
                                Label("Upgrade to CarCare Log Pro", systemImage: "star.fill")
                                Spacer()
                                Text("View").foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Restore Purchases") { Task { await store.restore() } }
                    if let m = store.purchaseMessage { Text(m).font(.caption).foregroundStyle(.secondary) }
                }

                Section("Preferences") {
                    Picker("Currency", selection: $currency) {
                        ForEach(AppSettings.currencies, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Distance units", selection: $distanceUnit) {
                        Text("Kilometres").tag("km"); Text("Miles").tag("mi")
                    }
                    Picker("Fuel efficiency units", selection: $efficiencyUnit) {
                        Text("km/L (or km/kWh)").tag("kmPerUnit"); Text("L/100 km (or kWh/100 km)").tag("per100"); Text("MPG (US)").tag("mpg")
                    }
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                    Picker("First day of the week", selection: $firstWeekday) {
                        Text("Sunday").tag(1); Text("Monday").tag(2)
                    }
                }

                Section {
                    Toggle("Enable reminders", isOn: $remindersEnabled)
                        .onChange(of: remindersEnabled) { _, on in
                            if on { Task { _ = await NotificationService.requestPermission(); rescheduleAll() } }
                            else { NotificationService.cancelAll() }
                        }
                    Toggle("Maintenance notifications", isOn: $maintenanceNotifications)
                        .onChange(of: maintenanceNotifications) { _, _ in rescheduleAll() }
                    Toggle("Insurance notifications", isOn: $insuranceNotifications)
                        .onChange(of: insuranceNotifications) { _, _ in rescheduleAll() }
                    Toggle("Registration notifications", isOn: $registrationNotifications)
                        .onChange(of: registrationNotifications) { _, _ in rescheduleAll() }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Reminders are local notifications. Permission is only requested when you turn reminders on — never at launch.")
                }

                Section("Reports & Data") {
                    NavigationLink("Vehicle Reports") { ReportsView() }
                    Button("Export All Data (Backup)") { exportBackup() }
                    Button("Import Backup (Merge)") { guardPro { importMode = "merge"; showImporter = true } }
                    Text("Merge keeps your current data and skips any vehicle whose ID already exists \u{2014} nothing is duplicated.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Restore From Backup (Replace All)") { guardPro { confirmRestore = true } }
                    Text("Restore replaces ALL current data with the backup, after the file passes full validation.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Clear All Data", role: .destructive) { confirmClear = true }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }

                Section("About") {
                    LabeledContent("App", value: "CarCare Log")
                    LabeledContent("Version", value: "1.0.2")
                    Link("Privacy Policy", destination: AppConfig.privacyURL)
                    Link("Terms of Use", destination: AppConfig.termsURL)
                    Link("Contact Support", destination: URL(string: "mailto:\(AppConfig.supportEmail)") ?? AppConfig.privacyURL)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
                if let items = shareItems { ShareSheet(items: items) }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .confirmationDialog("Replace ALL current data with this backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Choose Backup File\u{2026}") { importMode = "replace"; showImporter = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your existing vehicles and records will be deleted and replaced by the backup's contents. This cannot be undone.")
            }
            .confirmationDialog("Delete ALL vehicles and records?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear All Data", role: .destructive) {
                    for v in vehicles { context.delete(v) }
                    NotificationService.cancelAll()
                    message = "All local data cleared."
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone. Export a backup first if you may need this data.")
            }
        }
    }

    private func guardPro(_ action: () -> Void) {
        if store.isPro { action() } else { showPaywall = true }
    }

    private func rescheduleAll() {
        NotificationService.rescheduleAll(vehicles: vehicles, globalEnabled: remindersEnabled,
                                          maintenanceEnabled: maintenanceNotifications,
                                          insuranceEnabled: insuranceNotifications,
                                          registrationEnabled: registrationNotifications)
    }

    private func exportBackup() {
        do {
            let data = try BackupService.makeBackup(vehicles: vehicles)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("CarCareLog-Backup.json")
            try data.write(to: url)
            shareItems = [url]
        } catch {
            message = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { message = "Import cancelled."; return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let backup = try BackupService.decode(data)
            try BackupValidator.validate(backup)          // full validation first…
            let restored = BackupService.buildVehicles(from: backup) // …graph built detached…
            // …only now is the store touched (FIX 16). Two defined behaviours:
            if importMode == "replace" {
                // True restore: wipe existing data, then insert the backup.
                NotificationService.cancelAll()
                for v in vehicles { context.delete(v) }
                for v in restored { context.insert(v) }
                rescheduleAll()
                message = "Restored \(restored.count) vehicle(s): all previous data was replaced by the backup (records, photos, schedules, reminders, documents and mileage history included)."
            } else {
                // Merge: vehicles whose ID already exists are skipped entirely,
                // so re-importing the same backup never duplicates records.
                let existing = Set(vehicles.map { $0.id })
                let fresh = restored.filter { !existing.contains($0.id) }
                for v in fresh { context.insert(v) }
                rescheduleAll()
                let skipped = restored.count - fresh.count
                message = "Imported \(fresh.count) new vehicle(s)\(skipped > 0 ? "; \(skipped) already existed and were skipped (no duplicates)" : "")."
            }
                } catch {
            message = "That file is not a valid CarCare Log backup."
        }
    }
}
