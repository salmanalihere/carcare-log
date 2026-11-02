import SwiftUI
import SwiftData
import Charts

struct ExpensesView: View {
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @AppStorage(PrefKeys.selectedVehicleID) private var selectedVehicleID = ""
    @AppStorage(PrefKeys.currency) private var currency = "USD"
    @EnvironmentObject private var store: StoreManager
    @State private var segment = 0
    @State private var search = ""
    @State private var categoryFilter: ExpenseCategory? = nil
    @State private var sortByAmount = false
    @State private var showAdd = false
    @State private var showPaywall = false
    @State private var shareItems: [Any]? = nil
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"

    private var vehicle: Vehicle? { VehicleSelection.resolve(vehicles: vehicles, selectedID: selectedVehicleID) }

    var body: some View {
        NavigationStack {
            Group {
                if let v = vehicle {
                    VStack(spacing: 0) {
                        Picker("Section", selection: $segment) {
                            Text("Expenses").tag(0)
                            Text("Fuel").tag(1)
                            Text("Analytics").tag(2)
                        }
                        .pickerStyle(.segmented).padding()
                        switch segment {
                        case 1: FuelListView(vehicle: v)
                        case 2: analytics(v)
                        default: expenseList(v)
                        }
                    }
                } else {
                    EmptyStateView(icon: "creditcard.fill", title: "No vehicle yet",
                                   message: "Add a vehicle first, then record its expenses here.")
                }
            }
            .navigationTitle("Expenses")
            .sheet(isPresented: $showAdd) { if let v = vehicle { ExpenseEditorView(expense: nil, vehicle: v) } }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
                if let items = shareItems { ShareSheet(items: items) }
            }
        }
    }

    private func filteredExpenses(_ v: Vehicle) -> [Expense] {
        var list = v.expenses
        if let c = categoryFilter { list = list.filter { $0.category == c } }
        if !search.isEmpty { list = list.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.provider.localizedCaseInsensitiveContains(search) } }
        return list.sorted { sortByAmount ? $0.amount > $1.amount : $0.date > $1.date }
    }

    private func expenseList(_ v: Vehicle) -> some View {
        List {
            Section {
                HStack {
                    TextField("Search expenses", text: $search)
                    Menu {
                        Button("All Categories") { categoryFilter = nil }
                        ForEach(ExpenseCategory.allCases, id: \.self) { c in Button(c.rawValue) { categoryFilter = c } }
                    } label: { Label(categoryFilter?.rawValue ?? "Category", systemImage: "line.3.horizontal.decrease.circle") }
                }
                Toggle("Sort by amount (largest first)", isOn: $sortByAmount)
                LabeledContent("Total shown", value: currencyString(filteredExpenses(v).reduce(0) { $0 + $1.amount }, code: currency))
            }
            ForEach(filteredExpenses(v)) { e in
                NavigationLink { ExpenseEditorView(expense: e, vehicle: v) } label: {
                    HStack {
                        Image(systemName: e.category.icon).foregroundStyle(Color.ccAccent).frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(e.title).font(.headline).lineLimit(1)
                            Text("\(e.category.rawValue) · \(e.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(currencyString(e.amountStr, code: currency)).bold()
                    }
                }
            }
            Section {
                Button { showAdd = true } label: { Label("Add Expense", systemImage: "plus.circle.fill") }
            }
        }
    }

    private func analytics(_ v: Vehicle) -> some View {
        // Centralized totals (FIX 11/12) — identical definitions to Dashboard/Reports/PDF/CSV.
        let all = FinancialCalculationService.totals(for: v)
        let monthly = FinancialCalculationService.monthlyTotals(for: v)
        let breakdown = FinancialCalculationService.categoryTotals(for: v)
        return List {
            Section("Summary") {
                LabeledContent("Total ownership cost", value: currencyString(all.ownership, code: currency))
                LabeledContent("This year", value: currencyString(FinancialCalculationService.totals(for: v) { Calendar.current.isDate($0, equalTo: .now, toGranularity: .year) }.ownership, code: currency))
                LabeledContent("Average monthly cost", value: currencyString(FinancialCalculationService.averageMonthlyOwnership(for: v), code: currency))
                if let top = breakdown.first { LabeledContent("Highest category", value: "\(top.category) (\(currencyString(top.total, code: currency)))") }
            }
            Section("Monthly Expenses") {
                if monthly.allSatisfy({ $0.total == 0 }) { Text("No data yet.").foregroundStyle(.secondary) }
                else {
                    Chart(monthly, id: \.month) { item in
                        BarMark(x: .value("Month", item.month, unit: .month), y: .value("Amount", NSDecimalNumber(decimal: item.total).doubleValue))
                            .foregroundStyle(Color.ccAccent)
                    }.frame(height: 150)
                }
            }
            Section("Category Breakdown") {
                ForEach(breakdown, id: \.category) { row in
                    LabeledContent(row.category, value: currencyString(row.total, code: currency))
                }
            }
            Section("Reports") {
                Button("Export Expenses as CSV") { exportCSV(v) }
                Button("Generate PDF Report") { exportPDF(v) }
                if !store.isPro {
                    Text("PDF and CSV reports are CarCare Log Pro features.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func exportCSV(_ v: Vehicle) {
        guard store.isPro else { showPaywall = true; return }
        let csv = CSVExporter.reportCSV(dataset: ReportDataset.make(vehicle: v, periodLabel: "All Records", range: nil))
        if let url = CSVExporter.writeTempCSV(csv, name: "CarCareLog-Expenses.csv") { shareItems = [url] }
    }
    private func exportPDF(_ v: Vehicle) {
        guard store.isPro else { showPaywall = true; return }
        let data = PDFReportService.makeReport(vehicle: v, dataset: ReportDataset.make(vehicle: v, periodLabel: "All Records", range: nil), currency: currency, distanceUnit: distanceUnit)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CarCareLog-Report.pdf")
        if (try? data.write(to: url)) != nil { shareItems = [url] }
    }
}

struct ExpenseEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var expense: Expense?
    var vehicle: Vehicle

    @State private var title = ""
    @State private var category: ExpenseCategory = .other
    @State private var amount = ""
    @State private var date = Date.now
    @State private var odometer = ""
    @State private var provider = ""
    @State private var notes = ""
    @State private var error: String? = nil
    @State private var confirmDelete = false
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"

    var body: some View {
        NavigationStack {
            Form {
                Section("Expense") {
                    TextField("Title *", text: $title)
                    Picker("Category", selection: $category) { ForEach(ExpenseCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    TextField("Amount *", text: $amount).keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date)
                    TextField("Odometer (\(DistanceUnit.label(distanceUnit)))", text: $odometer).keyboardType(.decimalPad)
                    TextField("Service provider / shop", text: $provider)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                if let error { Text(error).foregroundStyle(Color.ccError) }
                if expense != nil {
                    Button("Delete Expense", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(expense == nil ? "Add Expense" : "Edit Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear(perform: load)
            .confirmationDialog("Delete this expense?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let e = expense { context.delete(e) }; dismiss() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func load() {
        if let e = expense {
            title = e.title; category = e.category; amount = e.amountStr; date = e.date
            odometer = e.odometer > 0 ? String(format: "%.0f", DistanceUnit.displayValue(km: e.odometer, unit: distanceUnit)) : ""; provider = e.provider; notes = e.notes
        }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Title is required."; return }
        guard let amt = Decimal(string: amount), amt > 0 else { error = "Amount must be greater than zero."; return }
        let odoDisplay = Double(odometer) ?? 0
        guard odoDisplay >= 0 else { error = "Odometer cannot be negative."; return }
        let odo = DistanceUnit.storedValue(display: odoDisplay, unit: distanceUnit) // display unit -> km
        if let e = expense {
            e.title = title; e.categoryRaw = category.rawValue; e.amountStr = Money.str(amt)
            e.date = date; e.odometer = odo; e.provider = provider; e.notes = notes
        } else {
            let newExpense = Expense(title: title, category: category, amount: amt, date: date,
                                     odometer: odo, provider: provider, notes: notes, vehicle: vehicle)
            context.insert(newExpense)
            if odo > 0 { MileageService.recordIfNeeded(vehicle: vehicle, odometer: odo, date: date, notes: "Expense: \(title)", context: context) }
        }
        dismiss()
    }
}
