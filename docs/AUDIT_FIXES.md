# CarCare Log — Audit Fixes 1.0.1 / 1.0.2

Applied to the existing 1.0 project in place. Bundle ID (`com.carcarelog.app`),
StoreKit product IDs, design and architecture unchanged. Version bumped to 1.0.1.

## FIX 1 — Complete backup & restore ✅
- Backup format is now **versioned (v2)** and contains everything: all vehicle
  fields (engine number, purchase date/price, insurance provider + expiry,
  registration expiry, created date), the **vehicle photo**, fuel entries with
  **receipt photos**, price-per-unit and notes, expenses with **receipt photos**,
  odometer and notes, maintenance records with receipts, next date/odometer and
  notes, **maintenance schedules**, **custom reminders**, and **documents with
  attachments** — plus the original record IDs, so notification identifiers
  stay stable after a restore. Photos/attachments travel as base64 in the JSON.
- **Backward compatibility:** all v2-only DTO fields are optional, so a v1
  (1.0.0) backup still decodes and restores; `formatVersion` absent ⇒ v1.
- **Validation before import:** `BackupValidator` checks the version range,
  year/odometer/amount sanity, every enum raw value, base64 integrity,
  document issue/expiry ordering, schedule shape and lead times.
- **Atomic import:** decode → validate → build the whole object graph detached
  → only then insert. A file that fails validation changes nothing.
- Covered by tests: full v2 round-trip (export → decode → validate → rebuild,
  asserting photos, receipts, schedules, reminders, documents and IDs), a v1
  JSON fixture, and rejection of a negative-amount and a future-version backup.
  The export → clear-all → restore cycle itself remains a manual Mac checklist
  item (see TEST_REPORT.md) because this VM has no Xcode/simulator.

## FIX 2 — Kilometres / miles done properly ✅
- One internal base unit: **kilometres**. Every stored odometer stays in km
  forever; changing the preference never rewrites stored data.
- New `DistanceUnit` service converts at the boundary only: display =
  km ÷ 1.609344, input = miles × 1.609344 back to km.
- Applied in: Dashboard mileage + distance-driven + next-maintenance remaining,
  vehicle list/detail, service history, PDF reports, and **every editor**
  (vehicle, fuel, expense, maintenance, schedule, quick mileage) — fields are
  labelled in the active unit, pre-filled with converted values, and converted
  back on save. Validation messages quote converted values.
- Fuel efficiency: km/L, L/100 km and **MPG (US)** are all supported
  (1 km/L = 2.35215 mpg), EV shows km/kWh, mi/kWh or kWh/100 (km or mi), and
  when miles are the preferred distance unit the per-litre display switches to
  MPG, the customary unit. Settings gains an explicit "MPG (US)" option.
- Tests assert conversion accuracy and round-trip losslessness in both units,
  plus exact formatted strings for km/L, L/100 km, MPG and kWh/100 km.

## FIX 3 — Notification management ✅ (as far as the brief received)
Note: the audit brief as received here ends mid-sentence in FIX 3
("Individual notification…"). Everything stated was implemented, plus the
category behaviour required by the original §9 brief:
- **Global toggle:** turning reminders off cancels ALL pending requests;
  turning it on requests permission and re-arms everything via
  `NotificationService.rescheduleAll`.
- **Category toggles** (maintenance / insurance / registration) now act
  immediately: `reschedule` actively **cancels** a category's pending requests
  when it is switched off and re-schedules them when switched back on —
  previously the toggles changed nothing.
- **Per-schedule switch** is honoured together with the global and category
  switches in the schedule editor (previously it scheduled even when the
  maintenance category was off).
- Insurance and registration keep distinct identifiers; document-expiry
  reminders follow their category (insurance/registration) switch.
- Saving a vehicle (insurance/registration expiry) or a document now re-arms
  that vehicle's reminders with the current switch states.
- If the rest of FIX 3 (or any FIX 4+) was cut off in transmission, send it
  and it will be applied the same way.

## Verification
Static verification PASS (project references both ways, brace balance,
JSON/scheme/plist validity, no force-unwraps/TODOs). Unit tests now 21
(written, not executed — no Swift toolchain on this Linux VM). Xcode build,
simulator and notification delivery remain Mac steps, unchanged from 1.0.

---

# 1.0.2 — Final Functional Corrections (2026-11-02)

Implemented in the same project; bundle ID and StoreKit IDs unchanged.

- **MileageEntry model (FIX 1–8):** new persistent SwiftData model
  (id, date, odometer in km, notes, Vehicle relationship, cascade delete),
  registered in the model container. Add Mileage now creates an entry;
  a dedicated Mileage History screen (Vehicle Details + Dashboard) lists,
  adds, edits and deletes real entries. Validation is chronological
  (previous ≤ candidate ≤ next; same-date entries order deterministically
  by (date, odometer, id)) so legitimate historical corrections pass and
  impossible ones are rejected. Dashboard monthly distance, current
  mileage, and maintenance remaining/due all read MileageEntry history;
  a single reading yields "not enough data", never a made-up distance.
  Fuel/service/expense odometer snapshots create deduplicated mileage
  entries via MileageService; a new vehicle's initial reading seeds history.
- **Centralized finance (FIX 11/12/15):** `FinancialCalculationService`
  is the single definition — Ownership = Fuel + Expenses + Maintenance,
  Decimal throughout. Dashboard, Vehicle Details (via totalExpenses),
  Analytics, Reports, PDF and CSV all use it.
- **Reports (FIX 9/10/13/14):** one `ReportDataset` filtered by the
  selected period feeds the preview, the PDF (tables and totals) and the
  CSV. The CSV now includes Maintenance rows and summary rows whose totals
  match the PDF exactly.
- **Backup v3 (FIX 16/17):** format incremented to v3 adding MileageEntry;
  v1/v2 files still restore. Restore behaviour is now explicit in Settings:
  **Merge** (keeps current data, skips vehicles whose ID already exists —
  no duplicates) and **Restore (Replace All)** behind a confirmation,
  both after full validation; a failed validation changes nothing.
- **Notifications (FIX 18):** identifiers are now namespaced —
  `cc-maintenance-{id}`, `cc-insurance-{vehicleID}`,
  `cc-registration-{vehicleID}`, `cc-document-{id}`, `cc-reminder-{id}` —
  so edits replace rather than duplicate, deletes/completions cancel the
  matching request, and category/global toggles cancel/reschedule exactly
  their own requests. Permission is still only requested when the user
  configures reminders.
- **Tests & honesty (FIX 19–21):** 30 test methods were written at that
  stage (counted from source); the final pre-Xcode pass below added the
  future-date and duplicate-detection tests, bringing the suite to 32. **None were executed** — Xcode build/test execution could
  not be performed in this environment (Linux VM, no Xcode). See
  docs/TEST_REPORT.md; it records written-vs-executed accurately.
- **Placeholders (FIX 23):** AppConfig values are marked
  `CONFIGURATION REQUIRED`; README and docs/APP_STORE.md list them as
  pre-submission steps. No real URLs were invented.
- **Audit sweep (FIX 24):** zero TODO/FIXME; the unused legacy CSV exporter
  and the unused fuel/maintenance-based distance helper were removed;
  no fake data, hardcoded dashboard numbers or local Pro unlocks exist —
  entitlement still comes only from verified StoreKit entitlements.

---

# Final Pre-Xcode Verification Pass (1.0.2)

- Mileage entries can no longer be future-dated: the rule is enforced in
  `MileageMath.isValid` (service layer), in `MileageService.recordIfNeeded`
  (automatic entries from fuel/expense/maintenance), in the backup validator,
  and the editor shows "Mileage date cannot be in the future." — the entered
  date is never silently rewritten.
- Exact duplicate manual mileage entries (same vehicle, date/time and
  odometer) are rejected with "An identical mileage entry already exists.";
  automatic deduplication is unchanged.
- PDF reports are paginated properly: consistent header and "Page X of N"
  footer on every page (two-pass rendering), section headings never sit
  alone at a page bottom, rows never cross the footer boundary.
- Documentation aligned to version 1.0.2 and Backup format v3.
- 32 test methods are written; automated execution has not yet been
  performed because the project has not been run with the Xcode/Swift
  toolchain. Xcode build and test execution remains required.
