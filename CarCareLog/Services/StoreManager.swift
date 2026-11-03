import Foundation
import StoreKit

/// StoreKit 2 manager. Entitlement comes ONLY from verified
/// `Transaction.currentEntitlements` — never from a local flag.
@MainActor
final class StoreManager: ObservableObject {
    static let monthlyID = "com.carcarelog.monthly.v2"
    static let yearlyID = "com.carcarelog.yearly"
    static let lifetimeID = "com.carcarelog.lifetime"
    static let productIDs = [monthlyID, yearlyID, lifetimeID]

    @Published var products: [Product] = []
    @Published var entitlement = PurchaseEntitlement()
    @Published var purchaseMessage: String? = nil
    @Published var isLoading = false

    private var listener: Task<Void, Never>? = nil

    init() {
        listener = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let tx) = result else { continue }
                await tx.finish()
                await self?.refreshEntitlements()
            }
        }
        Task { await loadProducts(); await refreshEntitlements() }
    }

    var isPro: Bool { entitlement.isPro }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { a, b in
                (Self.productIDs.firstIndex(of: a.id) ?? 0) < (Self.productIDs.firstIndex(of: b.id) ?? 0)
            }
        } catch {
            purchaseMessage = "Could not load prices from the App Store. Check your connection and try again."
        }
    }

    func refreshEntitlements() async {
        var active: PurchaseEntitlement? = nil
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result, Self.productIDs.contains(tx.productID) else { continue }
            if let expiry = tx.expirationDate, expiry < Date.now { continue }
            if tx.revocationDate != nil { continue }
            active = PurchaseEntitlement(isPro: true, productID: tx.productID, expirationDate: tx.expirationDate)
            if tx.productID == Self.lifetimeID { break }
        }
        entitlement = active ?? PurchaseEntitlement()
    }

    func purchase(_ product: Product) async {
        isLoading = true; defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let tx) = verification else {
                    purchaseMessage = "Purchase could not be verified."
                    return
                }
                await tx.finish()
                await refreshEntitlements()
                purchaseMessage = "Welcome to CarCare Log Pro."
            case .userCancelled:
                purchaseMessage = "Purchase cancelled."
            case .pending:
                purchaseMessage = "Purchase is pending approval. Pro unlocks automatically once approved."
            @unknown default:
                purchaseMessage = "Purchase did not complete."
            }
        } catch {
            purchaseMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restore() async {
        isLoading = true; defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            purchaseMessage = entitlement.isPro ? "Purchases restored — Pro is active." : "No active purchases were found for this Apple ID."
        } catch {
            purchaseMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    /// Free-plan gate: 1 vehicle without Pro.
    func canAddVehicle(currentCount: Int) -> Bool { isPro || currentCount < 1 }
}
