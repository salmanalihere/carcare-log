# StoreKit / App Store Connect Setup — CarCare Log

Create these products in App Store Connect under bundle ID `com.carcarelog.app`.
Product IDs must match `StoreManager.productIDs` exactly:

| Product ID | Type | Price target | Notes |
|---|---|---|---|
| `com.carcarelog.monthly.v2` | Auto-renewable subscription | $2.99 / month | Subscription group "CarCare Log Pro" |
| `com.carcarelog.yearly` | Auto-renewable subscription | $19.99 / year | Same group "CarCare Log Pro" |
| `com.carcarelog.lifetime` | Non-consumable | $39.99 | One-time unlock |

Rules the app follows (already implemented):
- Actual prices are always read from StoreKit (`product.displayPrice`) — the
  figures above are App Store Connect price targets, never shown hardcoded.
- Entitlement = verified `Transaction.currentEntitlements` only; expired or
  revoked transactions do not unlock Pro. Cancelled, failed and pending
  purchases all surface a message and never fake success.
- Restore uses `AppStore.sync()` then re-reads entitlements.

Local testing: the Xcode scheme loads `CarCareLog/CarCareLog.storekit`, which
mirrors these three products, so the paywall, purchase, restore and
expired-subscription states can be tested in the simulator's StoreKit
test environment before the App Store Connect products exist.
