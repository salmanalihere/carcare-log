# CarCare Log

**Your Car. Your Records. Always Under Control.**

Premium native iOS vehicle management app — fuel, expenses, maintenance, reminders, documents and total ownership cost, stored locally on device.

- Native Swift + SwiftUI, SwiftData, MVVM-style service layer, iOS 17+
- StoreKit 2, UserNotifications, Swift Charts, PhotosUI, native PDF (`UIGraphicsPDFRenderer`)
- Bundle ID: `com.carcarelog.app` · Display name: CarCare Log · Version 1.0.2
- No third-party dependencies, no account, no server. All data stays on the device.

## Build

1. Open `CarCareLog.xcodeproj` in Xcode 15+.
2. Set your signing team on the `CarCareLog` target.
3. Run on an iOS 17+ simulator or device. The scheme is bound to the local
   `CarCareLog.storekit` configuration so purchases can be tested without App Store Connect.

## Before App Store submission (owner steps)

1. CONFIGURATION REQUIRED — replace the marked placeholders in
   `CarCareLog/Models/Models.swift` (`AppConfig`): support email, privacy
   policy URL and terms URL, and host those pages. They are deliberate
   placeholders, not production values.
2. Create the three products in App Store Connect exactly as documented in
   `docs/STOREKIT_SETUP.md` (IDs must match `StoreManager.productIDs`).
3. Run the unit tests (⌘U) and the manual checklist in `docs/TEST_REPORT.md`
   on a Mac — this source was built and statically verified on a Linux VM,
   where Xcode builds are not possible.
4. Archive with a distribution certificate and upload.

## Architecture

- `Models/Models.swift` — SwiftData models (`Vehicle`, `FuelEntry`, `Expense`,
  `MaintenanceRecord`, `MaintenanceSchedule`, `VehicleDocument`, `ReminderItem`,
  `MileageEntry` — the dedicated persistent mileage history; dashboard distance,
  current mileage and maintenance due/remaining all read it, validated
  chronologically so historical corrections are allowed).
  Money is `Decimal` stored as a string for exact arithmetic; enums are stored
  as raw strings. Deleting a vehicle cascades to all of its records.
- `Services/Calculations.swift` — pure, unit-tested engine. Fuel efficiency uses
  the **full-tank method only** (distance between two full-tank fills ÷ fuel
  added in between); insufficient data returns `nil`, never a guessed figure.
  EV consumption is the same math in kWh (shown as km/kWh or kWh/100 km).
- `Services/StoreManager.swift` — StoreKit 2. Entitlement comes **only** from
  verified `Transaction.currentEntitlements`; nothing unlocks from a local flag.
  Free plan: 1 vehicle. Pro gates: extra vehicles, PDF/CSV reports, documents,
  backup import/restore.
- `Services/NotificationService.swift` — local notifications. Permission is
  requested only when the user enables reminders or saves a schedule with
  notifications — never at launch. Mileage-due status is computed in-app from
  the latest odometer (iOS cannot fire a notification from an odometer value).
- `Services/ExportService.swift` — one filtered `ReportDataset` feeds the
  Reports preview, PDF and CSV (maintenance included; totals identical),
  and the versioned JSON backup (v3, incl. mileage history; v1/v2 still
  restore) is fully decoded and validated before anything is inserted.
  Settings offers Merge import (existing vehicle IDs skipped, no duplicates)
  and a confirmed Restore that replaces all data.
- `FinancialCalculationService` (in Calculations.swift) is the single totals
  definition everywhere: Ownership = Fuel + Expenses + Maintenance (Decimal).
- Views: 5 tabs — Dashboard (greeting, vehicle switcher, 4 stat cards, quick
  actions, Charts, recent activity), Vehicles (list, detail, documents,
  service history), Expenses (expenses + fuel + analytics segments, search /
  category filter / sorting), Maintenance (schedules grouped by
  Upcoming / Due Soon / Overdue / Completed + history), Settings
  (preferences, notifications, data, premium, about). Plus welcome/first-vehicle
  flow, paywall, and a dedicated Reports screen.

Colour palette: charcoal `#17191D`, almost black `#101114`, background
`#F5F6F8`, accent green `#30B879`, grey `#858B95`, warning `#F2A444`,
error `#E45B5B`. Light and Dark Mode both supported.
