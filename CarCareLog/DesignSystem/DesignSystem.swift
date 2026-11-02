import SwiftUI

extension Color {
    static let ccCharcoal = Color(red: 0x17 / 255, green: 0x19 / 255, blue: 0x1D / 255) // #17191D
    static let ccAlmostBlack = Color(red: 0x10 / 255, green: 0x11 / 255, blue: 0x14 / 255) // #101114
    static let ccBackground = Color(red: 0xF5 / 255, green: 0xF6 / 255, blue: 0xF8 / 255) // #F5F6F8
    static let ccAccent = Color(red: 0x30 / 255, green: 0xB8 / 255, blue: 0x79 / 255) // #30B879
    static let ccGrey = Color(red: 0x85 / 255, green: 0x8B / 255, blue: 0x95 / 255) // #858B95
    static let ccWarning = Color(red: 0xF2 / 255, green: 0xA4 / 255, blue: 0x44 / 255) // #F2A444
    static let ccError = Color(red: 0xE4 / 255, green: 0x5B / 255, blue: 0x5B / 255) // #E45B5B

    static var ccCard: Color { Color(UIColor.secondarySystemGroupedBackground) }
    static var ccScreen: Color { Color(UIColor.systemGroupedBackground) }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.ccCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}
extension View {
    func ccCard() -> some View { modifier(CardModifier()) }
}

func currencyString(_ amount: Decimal, code: String) -> String {
    Money.format(Money.str(amount), currency: code)
}
func currencyString(_ stored: String, code: String) -> String {
    Money.format(stored, currency: code)
}

extension MaintenanceMath.Status {
    var color: Color {
        switch self {
        case .upcoming: return .ccAccent
        case .dueSoon: return .ccWarning
        case .overdue: return .ccError
        case .completed: return .ccGrey
        }
    }
    var label: String {
        switch self {
        case .upcoming: return "Upcoming"
        case .dueSoon: return "Due Soon"
        case .overdue: return "Overdue"
        case .completed: return "Completed"
        }
    }
}

struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 38)).foregroundStyle(Color.ccGrey)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(.ccAccent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

struct StatusBadge: View {
    var status: MaintenanceMath.Status
    var body: some View {
        Text(status.label)
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(status.color.opacity(0.15))
            .foregroundStyle(status.color)
            .clipShape(Capsule())
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// The vehicle the user is currently looking at, resolved from the stored selection.
enum VehicleSelection {
    static func resolve(vehicles: [Vehicle], selectedID: String) -> Vehicle? {
        if let match = vehicles.first(where: { $0.id.uuidString == selectedID }) { return match }
        return vehicles.sorted { $0.createdAt < $1.createdAt }.first
    }
}

/// Display helper: stored kilometres -> "123 mi" / "123 km" in the user's unit.
func distText(_ km: Double, _ unit: String) -> String { DistanceUnit.formatted(km: km, unit: unit) }
