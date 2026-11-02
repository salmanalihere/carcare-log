import SwiftUI
import SwiftData

@main
struct CarCareLogApp: App {
    @StateObject private var store = StoreManager()
    @AppStorage(PrefKeys.appearance) private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
        .modelContainer(for: [
            Vehicle.self, FuelEntry.self, Expense.self,
            MaintenanceRecord.self, MaintenanceSchedule.self,
            VehicleDocument.self, ReminderItem.self, MileageEntry.self
        ])
    }
}
