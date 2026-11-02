import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @AppStorage(PrefKeys.hasCompletedWelcome) private var hasCompletedWelcome = false
    @State private var tab = 0
    @State private var showWelcome = false
    @State private var showAddVehicle = false

    var body: some View {
        TabView(selection: $tab) {
            DashboardView(goToVehicles: { tab = 1 })
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent") }
                .tag(0)
            VehiclesView()
                .tabItem { Label("Vehicles", systemImage: "car.2.fill") }
                .tag(1)
            ExpensesView()
                .tabItem { Label("Expenses", systemImage: "creditcard.fill") }
                .tag(2)
            MaintenanceView()
                .tabItem { Label("Maintenance", systemImage: "wrench.and.screwdriver.fill") }
                .tag(3)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(4)
        }
        .tint(.ccAccent)
        .onAppear { if !hasCompletedWelcome { showWelcome = true } }
        .sheet(isPresented: $showWelcome) {
            WelcomeView(onAddVehicle: { showWelcome = false; hasCompletedWelcome = true; showAddVehicle = true },
                        onSkip: { showWelcome = false; hasCompletedWelcome = true })
        }
        .sheet(isPresented: $showAddVehicle) {
            VehicleEditorView(vehicle: nil)
        }
    }
}

/// Simple first-launch experience: benefit, then add the first vehicle (skippable).
struct WelcomeView: View {
    var onAddVehicle: () -> Void
    var onSkip: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "car.front.waves.up.fill")
                .font(.system(size: 64)).foregroundStyle(Color.ccAccent)
            Text("CarCare Log").font(.largeTitle.bold())
            Text("Your Car. Your Records. Always Under Control.")
                .font(.headline).foregroundStyle(.secondary)
            Text("Track fuel, servicing, repairs, insurance and total ownership costs for your vehicle — all in one place, stored privately on your device.")
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
            Button("Add My First Vehicle", action: onAddVehicle)
                .buttonStyle(.borderedProminent).tint(.ccAccent).controlSize(.large)
            Button("Skip for now", action: onSkip)
            Spacer().frame(height: 24)
        }
    }
}
