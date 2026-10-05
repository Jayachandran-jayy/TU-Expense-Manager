---
name: expense-tracker-dev
description: Architecture, database, parsing, and testing workflows for the TU Expense Tracker project.
---

# TU Expense Tracker Developer Guide

This skill covers the project structure, design invariants, database schema, SMS parsing rules, filter subsystem, Docker deployment, and developer workflows to guide development and maintenance.

---

> [!IMPORTANT]
> ### 📋 Mandatory Development Protocols
> 1. **Mandatory Planning Mode (`/plan`) Enforcement Protocol (P0 Invariant)**:
>    Whenever the user invokes `/plan` or requests planning mode:
>    - **STRICTLY READ-ONLY**: You MUST NOT edit, write, or delete any project files, and you MUST NOT execute any state-altering commands. Only read-only tools (`view_file`, code search, directory listing) are permitted.
>    - **Mandatory Implementation Plan Artifact**: You must research the task thoroughly and write an implementation plan artifact with `RequestFeedback: true` and `UserFacing: true` at `<Artifact Directory>/<plan_name>.md`.
>    - **Immediate Turn Halt**: Immediately after creating or updating the plan artifact, you MUST stop your turn without touching any code files.
>    - **Never Pre-empt Plan Approval**: Never edit files, stage changes, or start execution until the user has explicitly reviewed and approved the plan.
>
> 2. **Mandatory Documentation Synchronization Protocol**:
>    Whenever code changes, architectural enhancements, UI redesigns, database schema updates, or workflow improvements are made in this repository, **THEY MUST ALWAYS BE SYNCHRONIZED AND UPDATED IN BOTH**:
>    - **This developer skill (`.agents/skills/expense-tracker-dev/SKILL.md`)**
>    - **The project root documentation (`README.md`)**
>    Never leave the skill or `README.md` outdated after making feature additions or bug fixes.
>
> 3. **Mandatory Test-by-Default Protocol**:
>    Whenever any new feature, UI enhancement, architectural change, or bug fix is implemented, **IT MUST BE TESTED BY DEFAULT**:
>    - Add and update unit, widget, or integration tests covering all new logic, UI states, lifecycle hooks, and error handling.
>    - Always execute the full test suite (`flutter test`) and static analysis (`dart analyze`) to ensure a 100% pass rate and zero warnings.
>    - Never conclude a task or mark a feature complete without running and verifying the automated test suites.
>
> 4. **Mandatory Visual Asset & Screenshot Synchronization Protocol**:
>    Whenever any UI component, screen layout, theme/palette, feature workflow, or Android installation/permission step is added, redesigned, or updated, **THE RELEVANT SCREENSHOTS IN `docs/screenshots/` AND THEIR REFERENCES IN `README.md` MUST BE IMMEDIATELY RE-CAPTURED AND UPDATED**:
>    - If a feature or UI page changes (e.g. Dashboard donut/charts, Transactions cards/filters, Split editor, Merchant Defaults, Themes/OLED), launch the Android Virtual Device (`emulator-5554`), seed realistic demo data, navigate to the screen, and capture fresh high-resolution screenshots.
>    - If installation, permission, or Play Protect handling flows change, re-capture or update the system walkthrough graphics (`install_play_protect.png`, `install_restricted_settings.png`, `install_sms_permission.png`, `install_app_info.png`).
>    - Never leave stale, outdated, or mismatched screenshots in `docs/screenshots/` or `README.md` after modifying UI or user-facing flows.
>
> 5. **Mandatory 3-Stage Development Lifecycle & Remote Push Protocol**:
>    All repository development must strictly adhere to three distinct operational stages:
>
>    - **Stage 1: Plan Mode (`/plan`)**
>      - **STRICTLY READ-ONLY**: Do NOT edit, write, or delete any project files, and do NOT run any state-altering commands.
>      - Research the task, formulate the architecture, and generate the implementation plan artifact (`<plan_name>.md`) with `RequestFeedback: true`.
>      - **Immediate Turn Halt**: Stop immediately upon presenting the plan and wait for explicit user approval before touching code.
>
>    - **Stage 2: Accept Edit Mode (Plan Approved)**
>      - **LOCAL WORK ONLY**: Implement code changes, edit files, run `dart analyze`, and execute `flutter test`.
>      - Create local feature/bugfix branches and commit changes locally with clear messages.
>      - **ZERO REMOTE PUSHES**: You must NOT push anything to any remote repository (GitHub or GitLab) in this stage.
>      - When local tests pass and work is complete, present the summary to the user and await manual authorization to push.
>
>    - **Stage 3: Push & Release Mode (Triggered when user says "push" / "push the changes")**
>      - Once the user explicitly instructs to push, you have full authorization to complete the entire remote pipeline without intermediate pauses:
>        1. Push the branch to GitHub: `git push -u origin <branch>`.
>        2. Open the Pull Request: `gh pr create --base main --fill`.
>        3. Squash-merge the Pull Request: `gh pr merge --squash --delete-branch`.
>        4. Pull merged `main` locally: `git checkout main && git pull`.
>        5. Tag the release if required: `git tag vX.Y.Z && git push origin vX.Y.Z`.
>      - **Note on F-Droid Updates**: F-Droid inclusion MR !48556 has been merged! F-Droid's `checkupdates` bot automatically monitors Git tags (`vX.Y.Z`) on GitHub and updates `metadata/com.tu.expense.manager.yml` on `fdroiddata` on its own. **Manual GitLab MR updates to `fdroiddata` are NO LONGER NEEDED.**
>      - You do not need to pause for separate approvals between pushing, merging, and tagging once Stage 3 is authorized.
>
> 6. **Mandatory PR/MR Description Protocol**:
>    Whenever a new branch is created and a Pull Request (PR) or Merge Request (MR) is opened or updated, **YOU MUST GENERATE AND UPDATE THE RELEVANT MR/PR DESCRIPTION**:
>    - Provide a clear template with the title, summary of changes, and technical notes for reviewers.
>    - If updating an existing PR via GitHub CLI (`gh pr edit`), automatically apply the generated description.
>    - Never leave the user without a comprehensive description to copy-paste or submit when code is pushed to a branch.
>
> 7. **Official F-Droid Inclusion & Tag-Based Automated Updates (MR !48556 Merged)**:
>    TU Expense Tracker is officially merged into F-Droid (`fdroid/fdroiddata:master`, package ID: `com.tu.expense.manager`).
>    - **No Manual GitLab MR Updates**: Upstream releases are tracked automatically via F-Droid's `checkupdates` engine (`AutoUpdateMode: Version v%v`, `UpdateCheckMode: Tags`). Pushing a git tag (`vX.Y.Z`) is all that is required for F-Droid to automatically package and distribute new versions.
>    - **Split APK Version Codes Invariant**: Keep `version: X.Y.Z+<buildNumber>` in `pubspec.yaml` formatted so the build numbers correctly produce `<buildNumber>1` (`x86_64`), `<buildNumber>2` (`armeabi-v7a`), and `<buildNumber>3` (`arm64-v8a`).
>    - **In-App Updater Auto-Check Invariant**: `UpdatePrefs.autoCheckEnabled()` MUST remain `false` by default on clean installs.
>    - **Runtime F-Droid Store Detection**: Preserve intent checks (`fdroidrepo://`, `fdroidapp://`) and installer checks (`isFdroidStore()`) so the in-app updater is completely suppressed on F-Droid installs.
>    - **Fastlane Metadata & Assets**: Ensure `fastlane/metadata/android/en-US/full_description.txt` uses valid HTML (`<b>`, `<p>`, `<ul>`, `<li>`), never Markdown.
>    - **GitHub Release Asset Parity**: Pinned Flutter version and split APK filenames (`app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk`) in `.github/workflows/release.yml` must remain intact to ensure bit-for-bit reproducible build verification passes on F-Droid build servers.

---

## 1. Project Structure

The project is structured as a multi-platform Flutter app and a Dart CLI server:

- **`lib/src/core/`**: Shared core domain logic, parsers, models, and ledger view derivations (pure Dart, zero Flutter dependencies).
- **`lib/src/ui_shared/`**: Shared UI components, tokens, charts, formatting rules, and tabs (`DashboardTab`, `TransactionsTab`) shared between mobile and web.
- **`lib/src/mobile/`**: Mobile-specific shell (`HomeShell`), SQLite database (`AppDatabase`), screens, sync client, and background services.
- **`lib/src/web/`**: Web-specific shell (`WebShell`), desktop transactions table (`WebTransactionsView`), API client, and login screen.
- **`server/`**: Standalone backend server written in Dart (Shelf), storing JSON snapshots and queued edits.
- **`test/`**: Unit, widget, and integration tests across mobile and web shells.

---

## 2. Invariants & Ingestion Rules

- **Idempotency & Multi-Layer Deduplication**:
  - **SmsSource In-Memory Deduplication**: Tracks recent incoming SMS signatures in a bounded 60-second window to drop duplicate native broadcast events from multi-part SMS or carrier re-deliveries, and prevents duplicate telephony listener registrations.
  - **Sequential Ingestion Queue (`HomeShell._serializeSms`)**: Asynchronous serialization queue guarantees that live incoming SMS processing and batch inbox catch-up scans never execute concurrently or race.
  - **Asynchronous Background Ingestion (`MainActivity.kt`)**: Native Android SMS and MMS/RCS queries run on a dedicated background worker executor (`Executors.newSingleThreadExecutor()`) with batch text part loading (`content://mms/part`), completely decoupling heavy inbox scans from the Android UI thread and Flutter rasterizer to prevent any UI freezing during rescans.
  - **Database-Level Composite Deduplication (`AppDatabase.insertParsed`)**:
    - **Exact Natural Key**: `(amount, merchant, date, direction, reference)`.
    - **Reference Code Uniqueness**: Non-empty reference codes (UPI Ref, UTR, Refno) deduplicate across identical `amount + direction + reference`.
    - **Time Window & Date Fallback Tolerance**: Empty-reference transactions deduplicate across identical `amount + merchant (NOCASE) + direction` within a ±60-second window. Same-day whole-day fallback deduplication applies only to date-only SMS alerts lacking an explicit clock time (`hasExplicitTime == false`). Transactions with explicit clock times (e.g. card alerts) outside the 60-second window are recognized as distinct same-day transactions.
- **Tombstones**: Deletions write natural keys to `deleted_transactions`. Inbox rescans check this table to avoid re-importing deleted SMS alerts.
- **SMS Parsing**:
  - **No Keyword Scanning for Direction**: Transaction direction (debit vs. credit) comes strictly from the matched regex template, not keyword scans (prevents issues with merchant names containing words like "CREDIT").
  - **Flexible Merchant Separators & Time Formats**: Templates flexibly match `@`, `at`, `to`, `towards`, and `for` merchant separators, with support for timestamps with or without seconds (`HH:mm[:ss]` and optional `am`/`pm`), commas, dots, ISO formats, short dates with time (`DD-MM HH:mm`), and month-first formats (`Sep 21, 2026 at 11:20:00`).
  - **Accurate Clock Time Extraction & Arrival Fallback**: When an explicit clock time is present, `hasExplicitTime` is set to `true`. When absent (e.g. UPI alerts), `_withArrivalTime` adopts the SMS arrival time if it falls on the same date, otherwise defaulting to midnight. In manual entry prefill (`extractDateOnly`), the arrival time-of-day is preserved rather than defaulting to 12:00 AM.
  - **Merchant Gateway Prefix & Trailing Symbol Stripping (`cleanMerchantName`, `tuCleanMerchantName`)**: Automatically strips bank gateway transport prefixes (`UPI_`, `UPI-`, `UPI/`, `UPI `) and trailing `@` or `.` symbols from raw merchant strings at SMS parse time while preserving original merchant casing and non-empty fallbacks.
  - **HDFC RuPay Card UPI Template (`hdfc_card_upi`)**: Dedicated template matching multiline and single-line RuPay credit card UPI debit alerts (`Txn Rs.<amount> On <card> At <merchant> by UPI <ref> On <date>`), capturing short dates (`DD-MM` or `DD/MM`) and inferring year from message arrival (`receivedAt?.year ?? DateTime.now().year`) with `hasExplicitTime: false`.
  - **Payment Method Auto-Persistence**: Automatically saves `sms.paymentType` into the `payment_methods` table on ingestion.
  - **Instrument Auto-Extraction (`extractInstrumentOnly`)**: Extracts payment instruments (e.g. `HDFC Bank Card 8174`, `SBI A/c *1234`) directly from SMS bodies when prefilling manual entry in `AddTransactionScreen`.
  - **Transaction Merchant Rename (`updateTransactionMerchant`)**: Dedicated "Edit merchant" action in `TransactionActionsSheet` and `HomeShell` allows renaming raw terminal or gateway IDs directly on transactions, with an optional checkbox to update all past matching transactions.
- **Testing Safety Rule**: **NEVER test or install builds on real physical devices** (including CMF Phone 1 or any other device connected via wireless debugging or USB) because they hold real user financial data. **ALWAYS use an Android Virtual Device (VD emulator, e.g., `emulator-5554`) for all testing, verification, and inspection.**
- **Docker Environment Rule**: **STRICTLY use the local Docker server on your development machine.** **NEVER touch, connect to, or execute commands on the ZIMA OS Docker instance.**
- **Notes**: Notes are sanitized using `cleanNote()`, collapsing white space and capping notes at 140 characters (`kNoteMaxLength`).
- **Email Parsing & Ingestion Subsystem (`EmailParser`, `EmailService`, `EmailTransactionsScreen`)**:
  - **Zero-Cloud Local Parsing (`lib/src/core/email_parser.dart`)**: Deterministic regex templates for major Indian card/bank alerts (HDFC, ICICI, SBI Card, Axis, Yes Bank, Kotak, IndusInd, and generic fallback). 0 MB overhead, 0 runtime latency, and 100% offline privacy (no cloud or local LLM required).
  - **HTML Stripping & Entity Decoding**: `EmailParser.stripHtml()` handles tag removal, script/style deletion, whitespace normalization, and decodes named/hex/decimal HTML entities (`₹`, `&amp;`, `&nbsp;`, `&#8377;`, `&#x20B9;`).
  - **Direction Integrity**: Direction (`debit` vs `credit`) is strictly determined by matched template rules rather than naive keyword search.
  - **Conversion to `ParsedSms`**: `EmailTransaction.toParsedSms()` converts parsed emails directly to the core `ParsedSms` representation for consistent downstream validation and database insertion.
  - **Gmail IMAP TLS Integration (`lib/src/mobile/services/email_service.dart`)**: Connects over TLS to `imap.gmail.com:993` via `enough_mail` using a Gmail 16-character App Password (no GCP OAuth or Cloud Console credentials needed). Pre-filters by transactional keywords (`debited`, `spent`, `credited`, `received`, `txn`, `card`, `a/c`), configurable lookback (7, 14, 30 days), and persists dismissed email IDs in `SharedPreferences`.
  - **Manual Verification & Prefilled Add Screen**: Emails are NEVER inserted in bulk. Users select an email or paste email text, which navigates to `AddTransactionScreen` pre-filled with parsed amount, merchant, instrument, date, notes, and direction toggle (`Expense` vs `Income/Refund`) for manual verification before saving. If the email body has an explicit transaction time, it is preserved; if only a calendar date is present, it borrows the email arrival time (`item.date`) instead of falling back to midnight (12:00 AM).
  - **Duplicate Detection Badge**: Emails matching existing transactions in the ledger by amount, direction, merchant, or reference are marked with an `Added` badge to prevent accidental re-entry.

---

## 3. Filter Architecture & Multi-Select Interlinked Facets

Filtering is centralized in `lib/src/core/ledger_view.dart` via `deriveLedgerView()`.

### Bidirectional Facet Interlinking
The available choices for each facet dynamically reflect the current state of **all other** active filters:
- **Months**: `monthOptions(transactions, current: currentMonth, keep: requested.months, categoryIds: requested.categoryIds, merchants: requested.merchants, paymentTypes: requested.paymentTypes)`
- **Categories**: `categoryOptions(transactions, allCategories, months: requested.months, merchants: requested.merchants, paymentTypes: requested.paymentTypes)`
- **Merchants**: `merchantOptions(transactions, months: requested.months, categoryIds: requested.categoryIds, paymentTypes: requested.paymentTypes)`
- **Cards / Accounts**: `paymentTypeOptions(transactions, months: requested.months, categoryIds: requested.categoryIds, merchants: requested.merchants)`

### Pruning Invariants
When filters change:
- `pruneSelection()` ensures multi-select sets (`categoryIds`, `merchants`, `paymentTypes`) only retain values that still exist in the constrained options.
- Month selections remain sticky and are preserved even across empty search queries.

### Shared Filter UI Controls (`lib/src/ui_shared/shared_controls.dart`)
- **`FilterTriggerButton`**: Renders trigger buttons with inactive ghost state and active light-blue pill state with count badges (`[1]`, `[2]`).
- **`ActiveFilterChipToken`**: Removable chip with subtle border, 11px font, and explicit `✕` close icon for each active selection.
- **`ActiveFiltersBar`**: Horizontal scrollable container for active chips with a right-aligned `Clear all` button.
- **`chooseMany`**: Reusable modal sheet supporting multi-select checkboxes for all facets.

---

## 4. UI Patterns, Multi-Theme System, Category Emojis & Cards

- **Category Emojis, Custom Icons & Multi-Style Icon Packs (`lib/src/ui_shared/palette.dart`, `categories_screen.dart`, `models.dart`)**:
  - **Vibrant WhatsApp / Fluent Style Category Emojis**: Every category has a colorful emoji representation. Defaults include 🛒 Grocery, 🍔 Food, ⛽ Fuel, 🛍️ Shopping, 💡 Bills & Utilities, ✈️ Travel, 🎬 Entertainment, 💊 Health, ❓ Uncategorized, 💰 Income/Savings, 🏦 Loans/EMI, 🥚 Egg, 🍗/🥩/🐟 Non-Veg/Meat/Fish, 👨 Papa/Family, 💄 Cosmetics/Beauty, 🥛 Milk/Dairy, 🍿 Snacks, and 🥗 Veggies/Fruits.
  - **Smart Automatic Keyword Matching & Legacy Fallback Upgrade (`suggestCategoryEmoji`, `categoryEmoji`, `categoryVectorIcon`)**: Automatically suggests contextual emojis and vector icons when typing category names (e.g. coffee/cafe -> ☕, loans/emi/debt -> 🏦, egg/anda/omelet -> 🥚, non-veg/chicken/biryani -> 🍗, meat/mutton -> 🥩, fish/seafood -> 🐟, papa/family/dad -> 👨, savings/deposit -> 💰, cosmetics/makeup -> 💄, milk/dairy -> 🥛, snacks/bakery -> 🍿, veggies/fruits/salad -> 🥗, rent/house -> 🏠, gym/fitness -> 🏋️, cab/uber -> 🚕, pet/dog -> 🐾, gaming/steam -> 🎮, books/college -> 📚, salon/hair -> ✂️, bills -> 💡, crypto/stocks -> 📈, etc.). `categoryEmoji()` automatically upgrades legacy fallback records (`icon == '🏷️'` or empty) to contextual emojis.
  - **Interactive Category Editor Sheet (`_CategoryEditorSheet`)**: Features a live squircle emoji avatar preview, real-time auto-suggestion based on input text, a curated quick-pick emoji selector grid (`kCuratedCategoryEmojis`), custom emoji text input, and full edit/rename support.
  - **End-to-End Category Icon Propagation (Mobile, Web & Shared UI)**: User-customized category icons saved in SQLite `categories.icon` are exported into JSON backup snapshots (`BackupData.categories`) and parsed by `SnapshotStore.fromBackup`. All shared and web views (`WebTransactionsView` category pills, `_FacetMenu` options, `_TransactionsSummary` breakdown chips, `_DashboardTabState` charts/ranked bars/table bodies, and `MerchantDefaultsScreen`) propagate `explicitIcon` to `CategoryAvatar` so custom category icons reflect consistently everywhere across both platforms.
  - **App Icon Packs (`AppIconPack`)**: Supports 3 distinct visual styles: `AppIconPack.emojis` (vibrant emoji avatars), `AppIconPack.outlined` (clean monochrome outline vector icons mapped via `categoryVectorIcon`), and `AppIconPack.filled` (modern solid filled vector icons). Configurable via `ThemeController.setIconPack()` and accessible in both Mobile Settings and the Web Appearance popup menu.
- **Modern Fintech Rounded Transaction Cards (`lib/src/ui_shared/transactions_tab.dart`)**:
  - **Copilot / Revolut Inspired Card Design**: 16px corner radius (`BorderRadius.circular(16)`), subtle outline border with elevation 0.
  - **Tinted Squircle Badges**: 44x44 tinted squircle avatar (`BorderRadius.circular(12)`) featuring a 15% alpha background tint of the category chart hue and 30% alpha outline border, enclosing a bold 22px category emoji (or `💰` for credits).
  - **Clear Typography & Directional Color**: Bold merchant titles, subtext for account & date metadata, 8px rounded category badge with border, and right-aligned bold amounts with explicit `+` (accent green) for credits and `-` for debits.
- **Multi-Theme & Pitch Black OLED Architecture (`lib/src/ui_shared/theme.dart`, `theme_models.dart`, `theme_controller.dart`)**:
  - **Two-Tier Customization**: Base mode (`AppThemeMode`: `system`, `light`, `dark`, `oled`) + Accent color palette (`AppAccentColor`: `blue`, `red`, `green`, `purple`, `orange`, `pink`, `cyan`, `amber`) + Icon Pack (`AppIconPack`: `emojis`, `outlined`, `filled`).
  - **Pitch Black OLED Mode**: Pure `#000000` pitch black scaffold, app bar, and bottom navigation bar backgrounds paired with `#121418` deep obsidian card and dialog containers, providing true black pixel shut-off for OLED displays while preserving structural visual hierarchy.
  - **State Management & Persistence**: `ThemeController` (singleton `ChangeNotifier`) automatically persists preferences via `ThemePrefs` (`theme.mode`, `theme.accent`, `theme.icon_pack`) and seamlessly synchronizes active theme across both Mobile (`TuExpenseTrackerApp`) and Web (`WebApp`, `WebShell`).
  - **Web Theme Menu & Branded Header (`WebShell._themeMenu`, `WebShell.appBar`)**: Features a branded app logo badge next to the title in the top app bar, alongside a dropdown menu providing instant switching for Theme Mode, Accent Color, and Icon Pack.
  - **Web Branding & Metadata**: Web build assets (`web/favicon.png`, `web/icons/Icon-*.png`, `assets/icon/app_icon.png`, `web/index.html`, `web/manifest.json`) are branded with the custom TU Expense Tracker app icon and metadata, replacing default Flutter placeholder assets.
- **Password Visibility Toggle**: All credential and password input fields (e.g. `_CredentialsDialog` on mobile and `LoginScreen` on web) must include an eye icon button (`IconButton`) toggling `obscureText` between masked and visible states.
- **Active Filter Display**: Filter selections are presented immediately as individual removable tokens in `ActiveFiltersBar`.
- **Visual Loading Modals & Coin Progress Bar (`lib/src/ui_shared/loading_dialog.dart`)**:
  - **`AnimatedCoin`**: Custom-rendered 3D rotating metallic currency coin with perspective projection and floating bob effect.
  - **`CoinProgressBar`**: Pill-shaped capsule progress track with animated multi-stop gradient shimmer sweep.
  - **`LoadingModal` & `withLoadingModal<T>()`**: Reusable non-dismissible modal dialog and async wrapper that provides clear visual feedback during blocking operations (initial SMS parsing, manual inbox rescans, database export/restore, server sync, authentication, and batch tombstone restores), ensuring clean dismissal in `finally` blocks upon completion or error.
- **`UndoToast` Floating Custom Notification (`lib/src/mobile/widgets/undo_toast.dart`)**:
  - **Overlay Queue**: Replaces native `SnackBar` for destructive actions (deletions, merges). Floats above the bottom navigation bar with a dark card UI.
  - **Animation & Dismiss**: Pops in via scale/fade. Auto-dismisses after 10 seconds via a visible shrinking `LinearProgressIndicator` timer bar at the bottom of the card, or manually via an `X` icon.
  - **Context & Controller Support**: Screens can either wrap their root `Scaffold` in `UndoToast(controller: _controller, child: ...)` passing a dedicated `UndoToastController`, or call `UndoToast.controllerOf(context).show(...)` / `UndoToast.maybeControllerOf(context)`.
- **Payment Method Alias Resolution in Deduplication & Entry (`MergeNamesScreen`, `HomeShell._openAddTransaction`)**:
  - Payment methods loaded from the `payment_methods` table are resolved through `NameAliases` (`aliases.resolve(NameKind.card, pm)`).
  - Already-merged cards fold cleanly into their canonical card name, preventing phantom duplicate merge suggestions under "Looks like duplicates" and redundant 0-count entries in "All cards & accounts".
  - Suggestion cards (`_SuggestionCard`) are interactive via `InkWell` so tapping anywhere on the card or the button initiates the merge dialog.
- **Reactive Split Auto-Balancing (`SplitScreen`, `AddTransactionScreen`, `core/splits.dart`)**:
  - The last row in a split builder always automatically carries the remaining balance (`withRemainderInLast`).
  - Editing any row above the last row dynamically recalculates and updates the balance into the last row in real time on every keystroke, ensuring figures stay balanced without requiring manual calculation or pressing an auto-balance button.
  - Editing the last row directly is preserved as manual input without auto-overwriting, immediately highlighting any unbalanced difference with a difference banner (`Allocated ₹X of ₹Y (Difference: ₹Z)`), with an auxiliary "Auto-balance" button to snap the last row back to the true balance on demand.
  - Consistent across existing transaction splits (`SplitScreen`) and new entries across all entry points (`AddTransactionScreen` via `+`, Email transactions, and unadded SMS).

---

## 5. Database Schema Reference

SQLite database runs on version 14 (`kSchemaVersion = 14`):
- `categories`: Available expense categories (`id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL COLLATE NOCASE, icon TEXT NOT NULL DEFAULT '', color INTEGER`).
- `merchant_mappings`: Direct `merchant_name` (PK, NOCASE) to `category_id` mapping.
- `name_aliases`: Merged merchant or payment type labels.
- `transactions`: Core transaction records.
- `transaction_splits`: Category & amount breakdown lines for split transactions.
- `deleted_transactions`: Tombstone keys.
- `app_meta`: Persistent metadata (e.g., `last_scanned_sms_date`).
- `payment_methods`: Table tracking unique payment instruments and methods (`name TEXT PRIMARY KEY COLLATE NOCASE`), auto-populated from parsed SMS alerts and manual entries.

> [!NOTE]
> - In schema v8, the `icon` column stores custom category emojis. When empty, `categoryEmoji(name)` falls back to seeded emojis and smart keyword matching.
> - In schema v9, bank gateway transport prefixes (`UPI_`, `UPI-`, `UPI/`, `UPI `) are automatically stripped across `transactions`, `merchant_mappings`, `deleted_transactions`, and `name_aliases` during migration, with automatic collision resolution preserving non-UPI category mappings and deduplicating matching natural keys.
> - In schema v14, the `payment_methods` table is introduced to persist discovered accounts and cards so they remain selectable across manual entry and filtering without being lost if transactions are modified.
> - For split transactions, `transactions.category_id` is a denormalized cache storing the ID of the split line with the highest amount. This dominant category is used for fallback sorting and display.

---

## 6. Docker & Multi-Platform Deployment

### Building & Running Local Docker Server
```bash
# Build the local server and web client
docker build -t tu-expense-server .

# Run container exposing port 8099
docker run -d \
  --name tu-expense-server \
  -p 8099:8099 \
  -v tu-expense-data:/data \
  -e EXPENSE_ADMIN_USER=jay \
  -e EXPENSE_ADMIN_PASSWORD=adminpassword123 \
  tu-expense-server:latest
```

### Network Bridging: Android Emulator to Host Docker
> [!IMPORTANT]
> When connecting the Android Virtual Device (VD) to Docker on Mac/PC:
> - **Do NOT use `localhost`** (it routes to the Android emulator itself).
> - Use the Android emulator loopback alias: **`http://10.0.2.2:8099`** or the Mac's LAN IP (e.g., `http://192.168.1.x:8099`).

### Automated Rolling Backup & Restore Architecture
- **Scheduled Auto-Backup**: `BackupScheduler` runs daily at 21:00 (9:00 PM) local container time (`TZ`), configurable via `BACKUP_HOUR` and `BACKUP_MINUTE` env vars.
- **Atomic Bundle & Rolling Retention**: `BackupManager` packages full server state (`users.json`, `sessions.json`, and all device subtrees) into `/data/backups/backup_<timestamp>.json`, enforcing a 10-slot rolling FIFO cap (oldest auto/manual snapshot deleted upon the 11th).
- **API Surface**:
  - `GET /api/v1/backups`: Lists snapshots and schedule status.
  - `POST /api/v1/backups`: Creates on-demand server snapshot.
  - `POST /api/v1/backups/<id>/restore`: Performs safe server state restoration.
- **Safety Shield on Restore**:
  - Server automatically creates a pre-restore safety copy (`safety_...`) before applying the archive.
  - Mobile app takes a local database safety export before overwriting local SQLite state with restored snapshot data.
  - Safety copies do not count towards the 10 rolling auto-save slots.
- **CLI Trigger**:
  ```bash
  docker exec -it tu-expense-server /app/server --backup-now
  ```

---

## 7. Developer Workflows & Commands

### Testing & Static Analysis
- Run all tests: `flutter test`
- Run static analysis: `dart analyze`
- Run specific test: `flutter test test/web_shell_test.dart`

> [!TIP]
> When writing widget tests for forms or scrollable bottom sheets, the default 800x600 test viewport will cause clipping and tap failures. Set a taller viewport size in widget tests:
> ```dart
> tester.view.physicalSize = const Size(800, 1600);
> tester.view.devicePixelRatio = 1.0;
> addTearDown(() => tester.view.resetPhysicalSize());
> ```

### Building & Running on Android Emulators
1. **List emulators**: `android emulator list`
2. **Start emulator**: `android emulator start <name>` (e.g., `cmd_phone_1`)
3. **Build debug APK**: `flutter build apk --debug`
4. **Install APK**: `/Users/jay/Library/Android/sdk/platform-tools/adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk`
5. **Launch Application**:
   ```bash
   /Users/jay/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell monkey -p com.tu.expense.manager -c android.intent.category.LAUNCHER 1
   ```

### Emulator Database Inspection & Seeding
Directly query or seed the isolated SQLite database on an Android emulator:
```bash
# Query categories
adb -s emulator-5554 shell "run-as com.tu.expense.manager sqlite3 databases/expense_manager.db 'SELECT * FROM categories;'"

# Query transactions count
adb -s emulator-5554 shell "run-as com.tu.expense.manager sqlite3 databases/expense_manager.db 'SELECT COUNT(*) FROM transactions;'"

# Seed SQL file from host to emulator DB
adb -s emulator-5554 push seed.sql /data/local/tmp/seed.sql
adb -s emulator-5554 shell "run-as com.tu.expense.manager sqlite3 databases/expense_manager.db < /data/local/tmp/seed.sql"
```

---

## 10. 📸 Visual Asset & Screenshot Capture Workflow

Whenever a UI redesign, new feature, theme update, or installation step changes, developers must update the screenshot assets in `docs/screenshots/` and update `README.md`.

### Screenshot Standards
- **Device & Environment**: Exclusively use the Android Virtual Device (e.g., `emulator-5554` / `cmd_phone_1`). **Never** connect or capture physical devices.
- **Theme**: Default to Dark Mode / Pitch Black OLED for visual consistency across documentation.
- **Sample Data**: Ensure realistic demo data (realistic merchant names, amounts, categories, and split rows) is seeded into the database before capturing so cards and charts look clean and professional.
- **Resolution**: Native device resolution (1080x2400 or crisp 1080px width).

### Capture Commands & Navigation
1. **Inspect UI Layout & Tap Coordinates**:
   ```bash
   android layout --device=emulator-5554
   ```
2. **Navigate & Tap Elements**:
   ```bash
   # Tap specific coordinates (e.g. Transactions tab)
   adb -s emulator-5554 shell input tap <X> <Y>
   ```
3. **Capture PNG Directly to `docs/screenshots/`**:
   ```bash
   # Capture active screen
   adb -s emulator-5554 exec-out screencap -p > docs/screenshots/<screen_name>.png
   ```

### Standard Screenshot Asset Index
| File Name | Screen / Purpose | Location in README |
| :--- | :--- | :--- |
| `dashboard.png` | Spend overview card, donut chart, category rank list | Visual Tour (Row 1) |
| `transactions.png` | Rounded cards, category badges, split indicators, search & filter chips | Visual Tour (Row 1) |
| `split_editor.png` | Multi-category split editor with remainder calculation | Visual Tour (Row 2) |
| `merchant_defaults.png` | Merchant category defaults (*Always ask me*, *Default*, *Not set*) | Visual Tour (Row 2) |
| `themes.png` | Theme mode selector, OLED toggle, accent color palette, icon packs | Visual Tour (Row 3) |
| `install_play_protect.png` | Play Protect dialog with expanded "More details" and "Install anyway" | Installation Guide (Step 2) |
| `install_restricted_settings.png` | App info screen with 3-dots menu open showing "Allow restricted settings" | Installation Guide (Step 3) |
| `install_sms_permission.png` | App permissions screen showing SMS permission set to Allow | Installation Guide (Step 4) |


### Multi-Month Comparison
The app features a full-screen `CompareMonthsScreen` that displays a side-by-side table of category spending across 2 to 6 selected months, along with delta columns (Δ amount and Δ %) for direct 2-month comparisons. The screen handles data from `spendByCategoryPerMonth`.

---

## 11. 📦 Official F-Droid Distribution & Automated Tag Updates

TU Expense Tracker is officially included in the canonical F-Droid repository ([`com.tu.expense.manager`](https://f-droid.org/packages/com.tu.expense.manager/)) via Merge Request [!48556](https://gitlab.com/fdroid/fdroiddata/-/merge_requests/48556), merged into `fdroid/fdroiddata:master` on October 1, 2026.

> [!NOTE]
> **Automated Updates Enabled**:
> The package metadata in `fdroiddata` is configured with `AutoUpdateMode: Version v%v` and `UpdateCheckMode: Tags`.
> **Manual GitLab MR updates to `fdroiddata` are NO LONGER NEEDED.** F-Droid's official `checkupdates` bot automatically detects upstream Git tags (`vX.Y.Z`) on GitHub, calculates the split APK version codes, and generates the build recipes automatically.

### Upstream Release Checklist & Invariants
Whenever cutting a new release (`vX.Y.Z`) upstream in `expense_manager`:
1. **Split APK Version Codes**:
   - In `pubspec.yaml`, set `version: X.Y.Z+<buildNumber>`.
   - The Flutter Gradle build generates three split APKs with the following version codes:
     - `x86_64`: `<buildNumber>1`
     - `armeabi-v7a`: `<buildNumber>2`
     - `arm64-v8a`: `<buildNumber>3`
   - *Example for v2.5.6 (`2.5.6+34`): codes are `341`, `342`, `343`.*
2. **In-App Updater Safeguards**:
   - `UpdatePrefs.autoCheckEnabled()` MUST remain `false` by default on clean installs.
   - `MainActivity.kt` and `update_service.dart` detect F-Droid intents (`fdroidrepo://`, `fdroidapp://`) and client packages, suppressing in-app update checks and showing *"Updates managed externally"* in Settings.
3. **Reproducible Builds & CI Asset Parity**:
   - Pinned Flutter version in `.github/workflows/release.yml` must match F-Droid's expectations.
   - Release workflow must publish assets with standard split names:
     - `app-arm64-v8a-release.apk`
     - `app-armeabi-v7a-release.apk`
     - `app-x86_64-release.apk`
4. **Publishing Workflow**:
   - Merge the release PR into `main`.
   - Tag the release: `git tag vX.Y.Z && git push origin vX.Y.Z`.
   - GitHub Actions automatically builds and publishes the release.
   - F-Droid's scheduled bot picks up the tag and builds the update automatically within 24–48 hours.
