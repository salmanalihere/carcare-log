import SwiftUI
import SwiftData
import Charts
import PhotosUI

struct FuelListView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(PrefKeys.currency) private var currency = "USD"
    @AppStorage(PrefKeys.efficiencyUnit) private var efficiencyUnit = "kmPerUnit"
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"
    var vehicle: Vehicle
    @State private var range: String = "All"
    @State private var showAdd = false
    private let ranges = ["This Week", "This Month", "3 Months", "This Year", "All"]

    private var filtered: [FuelEntry] {
        let cal = Calendar.current
        return vehicle.fuelEntries.filter { e in
            switch range {
            case "This Week": return cal.isDate(e.date, equalTo: .now, toGranularity: .weekOfYear)
            case "This Month": return cal.isDate(e.date, equalTo: .now, toGranularity: .month)
            case "3 Months": return e.date > (cal.date(byAdding: .month, value: -3, to: .now) ?? .distantPast)
            case "This Year": return cal.isDate(e.date, equalTo: .now, toGranularity: .year)
            default: return true
            }
        }.sorted { $0.date > $1.date }
    }

    private var fills: [FuelMath.Fill] {
        vehicle.fuelEntries.map { .init(odometer: $0.odometer, quantity: $0.quantity, isFullTank: $0.isFullTank, date: $0.date) }
    }

    var body: some View {
        List {
            Section {
                Picker("Period", selection: $range) { ForEach(ranges, id: \.self) { Text($0).tag($0) } }
                    .pickerStyle(.menu)
                LabeledContent("Total fuel spending", value: currencyString(filtered.reduce(0) { $0 + Money.dec($1.totalStr) }, code: currency))
                LabeledContent("Average price", value: averagePriceText)
                LabeledContent("Average consumption",
                               value: FuelMath.formattedEfficiency(kmPerUnit: FuelMath.kmPerUnit(fills: fills), unit: efficiencyUnit, isElectric: vehicle.fuelType.isElectric, distanceUnit: distanceUnit))
            }
            Section("Monthly Fuel Spending") {
                let monthly = ExpenseMath.monthlyTotals(items: vehicle.fuelEntries.map { .init(amount: Money.dec($0.totalStr), date: $0.date, category: "Fuel") })
                if monthly.allSatisfy({ $0.total == 0 }) {
                    Text("No fuel data yet.").foregroundStyle(.secondary)
                } else {
                    Chart(monthly, id: \.month) { item in
                        BarMark(x: .value("Month", item.month, unit: .month),
                                y: .value("Amount", NSDecimalNumber(decimal: item.total).doubleValue))
                        .foregroundStyle(Color.ccAccent)
                    }
                    .frame(height: 140)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            }
            Section("History") {
                if filtered.isEmpty {
                    Text("No fuel entries in this period.").foregroundStyle(.secondary)
                }
                ForEach(filtered) { e in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(e.date, style: .date).font(.headline)
                            Spacer()
                            Text(currencyString(e.totalStr, code: currency)).font(.headline)
                        }
                        Text("\(String(format: "%.2f", e.quantity)) \(e.fuelType.unitLabel) · \(distText(e.odometer, distanceUnit))\(e.isFullTank ? " · Full tank" : "")\(e.station.isEmpty ? "" : " · \(e.station)")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { context.delete(e) }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add Fuel Entry")
            }
        }
        .sheet(isPresented: $showAdd) { FuelEditorView(entry: nil, vehicle: vehicle) }
    }

    private var averagePriceText: String {
        let valid = vehicle.fuelEntries.filter { $0.quantity > 0 }
        guard !valid.isEmpty else { return "—" }
        let totalQty = valid.reduce(0.0) { $0 + $1.quantity }
        let totalCost = valid.reduce(0) { $0 + Money.dec($1.totalStr) }
        guard totalQty > 0 else { return "—" }
        let avg = totalCost / Decimal(totalQty)
        return "\(currencyString(avg, code: currency))/\(vehicle.fuelType.unitLabel)"
    }
}

struct FuelEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var entry: FuelEntry?
    var vehicle: Vehicle

    @State private var date = Date.now
    @State private var odometer = ""
    @State private var fuelType: FuelType = .petrol
    @State private var quantity = ""
    @State private var pricePerUnit = ""
    @State private var total = ""
    @State private var station = ""
    @State private var isFullTank = true
    @State private var notes = ""
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var receiptData: Data? = nil
    @State private var error: String? = nil
    @AppStorage(PrefKeys.distanceUnit) private var distanceUnit = "km"

    var body: some View {
        NavigationStack {
            Form {
                Section("Refuelling") {
                    DatePicker("Date", selection: $date)
                    TextField("Odometer (\(DistanceUnit.label(distanceUnit))) *", text: $odometer).keyboardType(.decimalPad)
                    Picker("Fuel type", selection: $fuelType) { ForEach(FuelType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    TextField("Quantity (\(fuelType.unitLabel)) *", text: $quantity).keyboardType(.decimalPad)
                        .onChange(of: quantity) { _, _ in recalcTotal() }
                    TextField("Price per \(fuelType.unitLabel) *", text: $pricePerUnit).keyboardType(.decimalPad)
                        .onChange(of: pricePerUnit) { _, _ in recalcTotal() }
                    TextField("Total amount paid *", text: $total).keyboardType(.decimalPad)
                        .onChange(of: total) { _, _ in recalcPrice() }
                    TextField("Fuel station", text: $station)
                    Toggle("Full tank", isOn: $isFullTank)
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("Receipt Photo", systemImage: "doc.text.image") }
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                Text("Efficiency is calculated only between full-tank fills, so partial fills never produce a misleading figure.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(Color.ccError) }
            }
            .navigationTitle(entry == nil ? "Add Fuel" : "Edit Fuel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, item in
                Task { if let data = try? await item?.loadTransferable(type: Data.self) { receiptData = data } }
            }
        }
    }

    private func recalcTotal() {
        if let q = Double(quantity), let p = Decimal(string: pricePerUnit), q > 0 {
            total = Money.str(Decimal(q) * p)
        }
    }
    private func recalcPrice() {
        if let q = Double(quantity), let t = Decimal(string: total), q > 0 {
            pricePerUnit = Money.str(t / Decimal(q))
        }
    }

    private func load() {
        fuelType = vehicle.fuelType
        if let e = entry {
            date = e.date; odometer = String(format: "%.0f", DistanceUnit.displayValue(km: e.odometer, unit: distanceUnit)); fuelType = e.fuelType
            quantity = String(e.quantity); pricePerUnit = e.pricePerUnitStr; total = e.totalStr
            station = e.station; isFullTank = e.isFullTank; notes = e.notes; receiptData = e.receiptData
        }
    }

    private func save() {
        guard let odoDisplay = Double(odometer), odoDisplay >= 0 else { error = "Enter a valid odometer reading."; return }
        let odo = DistanceUnit.storedValue(display: odoDisplay, unit: distanceUnit) // display unit -> km
        let others = vehicle.fuelEntries.filter { $0.id != entry?.id }
        if let prev = others.filter({ $0.date <= date }).map(\.odometer).max(), odo < prev {
            error = "Odometer is below an earlier fuel entry (\(distText(prev, distanceUnit))) on or before this date."; return
        }
        guard let qty = Double(quantity), qty > 0 else { error = "Quantity must be greater than zero."; return }
        guard let totalDec = Decimal(string: total), totalDec > 0 else { error = "Total amount must be greater than zero."; return }
        guard let priceDec = Decimal(string: pricePerUnit), priceDec >= 0 else { error = "Enter the price per \(fuelType.unitLabel)."; return }
        if let e = entry {
            e.date = date; e.odometer = odo; e.fuelTypeRaw = fuelType.rawValue; e.quantity = qty
            e.pricePerUnitStr = Money.str(priceDec); e.totalStr = Money.str(totalDec)
            e.station = station; e.isFullTank = isFullTank; e.notes = notes; e.receiptData = receiptData
        } else {
            let e = FuelEntry(date: date, odometer: odo, fuelType: fuelType, quantity: qty,
                              pricePerUnit: priceDec, total: totalDec, station: station,
                              isFullTank: isFullTank, notes: notes, vehicle: vehicle)
            e.receiptData = receiptData
            context.insert(e)
            // Fuel odometer snapshots also feed the dedicated mileage history (deduplicated, FIX 6).
            MileageService.recordIfNeeded(vehicle: vehicle, odometer: odo, date: date, notes: "Fuel entry", context: context)
        }
        dismiss()
    }
}
