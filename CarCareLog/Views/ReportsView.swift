import SwiftUI
import SwiftData

/// Dedicated reports: choose a vehicle and period, preview the summary,
/// then export a real PDF or CSV through the share sheet (Pro).
struct ReportsView: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @EnvironmentObject private var store: StoreManager
    @AppStorage(PrefKeys.currency) private var currency = "USD"
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"
    @State private var vehicleID = ""
    @State private var period = "This Month"
    @State private var shareItems: [Any]? = nil
    @State private var showPaywall = false
    private let periods = ["This Month", "This Year", "All Records"]

    private var vehicle: Vehicle? { VehicleSelection.resolve(vehicles: vehicles, selectedID: vehicleID) }

    private var range: DateInterval? {
        let cal = Calendar.current
        switch period {
        case "This Month": return cal.dateInterval(of: .month, for: .now)
        case "This Year": return cal.dateInterval(of: .year, for: .now)
        default: return nil
        }
    }

    var body: some View {
        List {
            if vehicles.isEmpty {
                Text("Add a vehicle to generate reports.").foregroundStyle(.secondary)
            } else {
                Section("Report") {
                    Picker("Vehicle", selection: $vehicleID) {
                        ForEach(vehicles) { v in Text(v.displayName).tag(v.id.uuidString) }
                    }
                    Picker("Period", selection: $period) { ForEach(periods, id: \.self) { Text($0).tag($0) } }
                }
                if let v = vehicle {
                    // Preview, PDF and CSV all use this ONE filtered dataset (FIX 9/14/15).
                    let dataset = ReportDataset.make(vehicle: v, periodLabel: period, range: range)
                    let t = dataset.totals
                    Section("Summary — \(period)") {
                        LabeledContent("Expenses (\(dataset.expenses.count))", value: currencyString(t.expenses, code: currency))
                        LabeledContent("Fuel (\(dataset.fuel.count))", value: currencyString(t.fuel, code: currency))
                        LabeledContent("Maintenance (\(dataset.maintenance.count))", value: currencyString(t.maintenance, code: currency))
                        LabeledContent("Grand total", value: currencyString(t.ownership, code: currency))
                    }
                    Section {
                        Button("Export PDF Report") { exportPDF(v) }
                        Button("Export CSV") { exportCSV(v) }
                        if !store.isPro { Text("Reports are a CarCare Log Pro feature.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle("Reports")
        .onAppear { if vehicleID.isEmpty { vehicleID = vehicle?.id.uuidString ?? "" } }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems { ShareSheet(items: items) }
        }
    }

    private func exportPDF(_ v: Vehicle) {
        guard store.isPro else { showPaywall = true; return }
        let data = PDFReportService.makeReport(vehicle: v, dataset: ReportDataset.make(vehicle: v, periodLabel: period, range: range), currency: currency, distanceUnit: distanceUnit)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CarCareLog-Report-\(period.replacingOccurrences(of: " ", with: "")).pdf")
        if (try? data.write(to: url)) != nil { shareItems = [url] }
    }
    private func exportCSV(_ v: Vehicle) {
        guard store.isPro else { showPaywall = true; return }
        let csv = CSVExporter.reportCSV(dataset: ReportDataset.make(vehicle: v, periodLabel: period, range: range))
        if let url = CSVExporter.writeTempCSV(csv, name: "CarCareLog-Report.csv") { shareItems = [url] }
    }
}
