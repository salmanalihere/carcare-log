# Test Report — CarCare Log 1.0.2

## Execution status (read this first)

**Xcode build/test execution could not be performed in this environment.**

This source was produced and statically verified on a Linux VM with no
Swift/Xcode toolchain. **No unit test has been executed. No build has been
run. The app is NOT claimed to be App Store ready.** Any number below is a
count of test methods *written*, taken from the source file — not a pass count.

## Test suite as written

- File: `CarCareLogTests/CarCareLogTests.swift`
- **32 test methods written, 0 executed.**

Coverage by area:
- Fuel efficiency: full-tank method, insufficient-data nil cases, zero-distance, cost per km.
- Expenses: totals, category breakdown, month-change edge case (nil with no last month).
- Maintenance status: overdue by date, due-soon by mileage, overdue-beats-due-soon, completed.
- Future-dated mileage rejected at the service layer; exact-duplicate
  detection (same date/time + odometer), with self-edit excluded.
- Mileage validation (legacy `>=` checks) **plus** the 1.0.2 chronological
  rules: historical correction allowed (10,500 → 10,400 between 10,000 and
  11,000), correction beyond the next reading rejected, newest/oldest edge
  rules, negative rejected.
- Monthly distance from MileageEntry history: baseline-before-month case,
  single-reading → nil, no-readings-in-month → nil.
- Distance/efficiency conversion: km↔mi accuracy and round-trips, km/L,
  L/100 km, MPG and reverse conversion, formatted strings, EV kWh/100 km.
- FinancialCalculationService: fuel-only, expense-only, maintenance-only,
  all pairwise combinations, all three (220), zero records, Decimal accuracy
  (0.1 + 0.2 + 0.3 = 0.6), and Vehicle.totalExpenses agreeing with the service.
- Reports: ReportDataset month filtering excludes out-of-period maintenance,
  All Records includes it, CSV contains maintenance rows and the correct
  ownership total, month CSV excludes the backdated record, PDF data is
  generated from the dataset with matching totals.
- Backup: v3 complete round-trip (photos, receipts, schedules, reminders,
  documents, IDs), mileage entries round-trip with vehicle relationship,
  v1 backup fixture still decodes/restores, validation rejects a negative
  amount, a negative mileage reading and an unsupported future version.
  (The "database unchanged after invalid import" property follows from the
  validate-then-build-then-insert order in SettingsView; it is covered by
  code structure, not by an executed integration test.)
- Notifications: the five namespaced identifier formats are exact and mutually
  unique (pure-function tests). Actual scheduling/cancellation behaviour in
  UNUserNotificationCenter can only be verified on a device/simulator.
- StoreKit: product ID contract, free-plan vehicle gate, and a fresh
  entitlement is never Pro (no fake local unlock). Purchase flows
  (verified/unverified/pending/cancelled/failed/expired/restore) require the
  StoreKit test environment on a Mac and are **not** executed.
- Money/CSV helpers: Decimal exactness, CSV escaping, Money string round-trip.

## Static verification (actually performed here, 2026-11-02)

- All Swift files present and referenced exactly once in `project.pbxproj`;
  every project reference exists on disk; object definitions unique.
- Brace/paren balance per file; JSON validity for `.storekit`, asset
  catalogs; scheme XML and `PrivacyInfo.xcprivacy` well-formed.
- Zero `TODO`/`FIXME` in sources. Placeholder production values are marked
  `CONFIGURATION REQUIRED` (see docs/APP_STORE.md).

## Manual checklist (owner, on a Mac — still required)

1. ⌘U — record the REAL executed count and result here after running.
2. Build for a simulator; check Light/Dark Mode and two iPhone sizes.
3. Add mileage entries out of order (historical correction) and confirm the
   chronological validation behaves as documented in MileageMath.
4. Add fuel/service records and confirm deduplicated mileage entries appear.
5. Reports: verify This Month / This Year / All Records produce identical
   totals across preview, PDF and CSV for the same vehicle.
6. Backup: export, Clear All Data, Restore (Replace All) and confirm all
   data returns incl. mileage history; re-import the same file with Merge
   and confirm no duplicates.
7. Notifications: toggle each switch off/on and inspect pending requests
   (e.g. via a debug print of `getPendingNotificationRequests`).
8. StoreKit test environment: purchase, cancel, pending, restore, expiry.
