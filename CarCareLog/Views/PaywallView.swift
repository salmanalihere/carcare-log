import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    private let freeFeatures = ["1 vehicle", "Fuel tracking", "Basic expense tracking", "Basic maintenance tracking", "Basic dashboard"]
    private let proFeatures = ["Unlimited vehicles", "Complete vehicle history", "Advanced fuel & expense analytics", "PDF and CSV reports", "Unlimited reminders", "Document management", "Advanced maintenance scheduling", "Multiple vehicle comparisons", "Complete backup & restore", "Advanced charts and insights"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "car.front.waves.up.fill").font(.system(size: 48)).foregroundStyle(Color.ccAccent)
                    Text("CarCare Log Pro").font(.largeTitle.bold())
                    Text("Every record for every car — unlimited, with full reports and documents.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 14) {
                        featureGroup(title: "Free", features: freeFeatures, pro: false)
                        featureGroup(title: "Pro", features: proFeatures, pro: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ccCard()

                    if store.products.isEmpty {
                        ProgressView("Loading App Store prices…")
                    } else {
                        ForEach(store.products) { product in
                            Button {
                                Task { await store.purchase(product) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(product.displayName).font(.headline)
                                        Text(product.description).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(product.displayPrice).font(.headline)
                                }
                                .padding()
                                .background(Color.ccAccent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .foregroundStyle(.primary)
                            .disabled(store.isLoading)
                        }
                    }
                    if let msg = store.purchaseMessage {
                        Text(msg).font(.subheadline).multilineTextAlignment(.center)
                    }
                    Button("Restore Purchases") { Task { await store.restore() } }
                    HStack(spacing: 16) {
                        Link("Terms of Use", destination: AppConfig.termsURL)
                        Link("Privacy Policy", destination: AppConfig.privacyURL)
                    }
                    .font(.caption)
                    Text("Prices are shown from the App Store for your region. Subscriptions renew automatically unless cancelled in Settings > Apple ID > Subscriptions. The lifetime option is a one-time purchase.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .navigationTitle("Go Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { if store.products.isEmpty { await store.loadProducts() }; await store.refreshEntitlements() }
            .onChange(of: store.isPro) { _, pro in if pro { dismiss() } }
        }
    }

    private func featureGroup(title: String, features: [String], pro: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(pro ? Color.ccAccent : .secondary)
            ForEach(features, id: \.self) { f in
                Label(f, systemImage: pro ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(pro ? .primary : .secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
    }
}
