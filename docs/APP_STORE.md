# App Store Submission Checklist — CarCare Log

1. Signing: select the team, keep bundle ID `com.carcarelog.app`, version 1.0.2 (build 1).
2. CONFIGURATION REQUIRED: replace `AppConfig` placeholders (support email, privacy URL, terms URL) in
   `CarCareLog/Models/Models.swift` and host the privacy policy page
   (see `PRIVACY_POLICY.md` — the app collects no data and has no tracking;
   `PrivacyInfo.xcprivacy` already declares no collected data types).
3. Create the 3 StoreKit products (`STOREKIT_SETUP.md`) and submit them with the build.
4. Screenshots: Dashboard, Fuel analytics, Maintenance schedules, Paywall.
5. App Privacy questionnaire: "Data Not Collected" (all records are on-device only;
   document/receipt photos are stored in the app's private container).
6. Run ⌘U (32 test methods are written; none have been executed yet — see
   `TEST_REPORT.md`) and the manual checklist, then Archive. Do not submit
   until a real Xcode build and test run have passed on a Mac.
