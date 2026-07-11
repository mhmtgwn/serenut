#!/bin/bash
# 🚀 SERENUT POS — ENGINEER START COMMANDS
# Copy-paste these into each engineer's Slack

# ════════════════════════════════════════════════════════════════════════════════
# COMMAND 1: FOR BACKEND / ARCHITECT ENGINEER
# ════════════════════════════════════════════════════════════════════════════════

cat << 'BACKEND_START'

🔥 BACKEND ARCHITECT — GO BUILD PHASE 0
═══════════════════════════════════════════════════════════════════════════════

Your mission: Freeze foundation (3-5 days parallel with UI team)

📄 PRIMARY SOURCE:
   → PHASE_0_FINAL_ENGINEERING_SPEC.md

🎯 WHAT YOU'RE BUILDING:
   ✅ Auth contract (local mock)
   ✅ AppState<T> pattern (Riverpod-ready)
   ✅ Error model (exception hierarchy + codes)
   ✅ TransactionEngine pseudo → Dart
   ✅ Rollback strategy (all-or-nothing)
   ✅ SQLite schema locked (18 tables)
   ✅ Event system design (6 event types)
   ✅ UI↔Backend contract rules

⏱️  TIMELINE:
   Day 1: Auth + State Pattern (6-8 hours)
   Day 2: Error Model + TransactionEngine (8-10 hours)
   Day 3: Rollback + Schema + Events (6-8 hours)
   Day 4-5: Polish + Zero ambiguity (4-6 hours)
   
   📍 SYNC POINT: Day 3 (30-min call with UI team)

✅ SUCCESS CRITERIA:
   ✓ AuthService compiles (all 3 mock users working)
   ✓ AppState<T> wrapper implemented (zero raw Future)
   ✓ Error codes locked (50+ codes, immutable)
   ✓ TransactionEngine pseudocode → Dart (all 3 methods atomic)
   ✓ Rollback tested (simulated failures roll back correctly)
   ✓ Schema verified (18 tables, constraints, indexes)
   ✓ Events immutable (6 types locked)
   ✓ Zero ambiguity (all design decisions final)

🚫 CONSTRAINT:
   ⚠️  Don't integrate UI yet (UI team is building mock layer)
   ⚠️  Don't write real repositories (that's PHASE 1.5)
   ⚠️  Focus: Contract frozen, zero breaking changes after Day 5

📋 DAILY CHECKLIST (Day 1-5):
   Day 1:
     - [ ] AuthService + AuthUser model
     - [ ] UserRole enum (admin/manager/cashier/staff)
     - [ ] AppState<T> wrapper + AsyncValue integration
     - [ ] Post: "✅ Auth + State Pattern done"

   Day 2:
     - [ ] AppException hierarchy (base class)
     - [ ] Error code enums (FINANCIAL_*, STOCK_*, PAYMENT_*)
     - [ ] TransactionEngine pseudocode analyzed
     - [ ] Post: "✅ Error Model + TransactionEngine start"

   Day 3:
     - [ ] TransactionEngine pseudo → Dart (all 3 methods)
     - [ ] RequiredDbExecutor rollback wrapper
     - [ ] Failure matrix (edge cases)
     - [ ] Post: "✅ TransactionEngine + Rollback done"
     - [ ] 🔔 SYNC CALL (30 min with UI team)

   Day 4-5:
     - [ ] Event system (6 domain events + EventPublisher)
     - [ ] UI↔Backend contract rules
     - [ ] Schema verification (DDL review)
     - [ ] Final sign-off (no more changes)
     - [ ] Post: "✅ PHASE 0 COMPLETE — Ready for integration"

🔗 DELIVERABLE:
   PHASE_0_FINAL_ENGINEERING_SPEC.md (updated with Dart code)
   → Updated sections: 1-8 with implementations
   → Git commit: "PHASE 0: Foundation freeze complete"

🎉 RESULT:
   After 5 days: ✅ Backend foundation 100% locked
   Waiting on: UI team (parallel track, same 5 days)
   Next: PHASE 1.5 Integration (both merge)

REFERENCE DOCS:
   • PHASE_0_FINAL_ENGINEERING_SPEC.md (your blueprint)
   • TERMINOLOGY_GLOSSARY.md (standard terms)
   • STOCK_TIMING_RULES.md (critical rules)
   • Field: Check Slack daily (UI team posts progress)

🚀 START NOW:
   1. Open PHASE_0_FINAL_ENGINEERING_SPEC.md
   2. Start Section 1 (Auth Contract)
   3. Post first commit by EOD: "PHASE 0: Auth contract ✅"

Questions? Ask now — don't guess!

═══════════════════════════════════════════════════════════════════════════════

BACKEND_START

# ════════════════════════════════════════════════════════════════════════════════
# COMMAND 2: FOR UI / FRONTEND ENGINEER
# ════════════════════════════════════════════════════════════════════════════════

cat << 'UI_START'

🔥 UI ENGINEER — GO BUILD PHASE 1 (Mock Layer)
═══════════════════════════════════════════════════════════════════════════════

Your mission: Build UI skeleton (3-5 days parallel with backend)

📄 PRIMARY SOURCE:
   → PHASE_1_PARALLEL_BUILD_PACKAGE.md

🎯 WHAT YOU'RE BUILDING:
   ✅ Riverpod DI container
   ✅ Bottom navbar (role-based tabs, Cupertino-style)
   ✅ 8 screen skeletons (all mock data)
   ✅ Router setup (go_router 8 routes)
   ✅ Shared widgets (search, selectors, dialogs - mock)
   ✅ Theme + styling (green #2E7D32, yellow #FFD600, red, orange)
   ✅ Mock repositories (fake products/customers/sales)

⏱️  TIMELINE:
   Day 1: Riverpod + mock data + theme (4-6 hours)
   Day 2: Router + navbar + login (4-6 hours)
   Day 3: Dashboard + Sales + Customers (6-8 hours)
   Day 4: Orders + Inventory + Payments (6-8 hours)
   Day 5: Reports + Settings + Widgets (6-8 hours)
   
   📍 SYNC POINT: Day 3 (30-min call with backend team)

✅ SUCCESS CRITERIA:
   ✓ All dependencies added (riverpod, go_router, shared_preferences)
   ✓ All 8 screens navigate correctly
   ✓ Login → Dashboard flow works (admin/cashier/manager)
   ✓ Navbar shows correct tabs per role
   ✓ Mock data loads with 300-500ms delay
   ✓ Dashboard KPI cards render (hardcoded values)
   ✓ Product/Customer lists populate from mock
   ✓ Cart adds/removes items (state updates)
   ✓ Settings toggle saves navbar visibility
   ✓ Zero compile errors
   ✓ No console errors (info hints OK)
   ✓ Responsive layout (portrait + landscape)

🚫 CRITICAL CONSTRAINTS (read carefully):

   ❌ DO NOT:
      ❌ Call TransactionEngine (not ready)
      ❌ Write to SQLite (disabled)
      ❌ Do payment processing (logic on backend)
      ❌ Calculate stock (backend does)
      ❌ Write ledger entries (backend only)
      ❌ Publish events (not yet)
      ❌ Call MathEngine (backend does calculations)
      ❌ Update customer balance manually

   ✅ DO:
      ✅ Use MockRepositories (return fake data + delay)
      ✅ Build UI forms (TextFields, buttons, inputs)
      ✅ Navigate screens
      ✅ Display mock data
      ✅ Implement loading/error states
      ✅ Save UI preferences (localStorage)
      ✅ Show mock errors gracefully

   ⚠️  WHY?
      UI and backend build in parallel. Backend is freezing contracts.
      Once locked (Day 5), you swap mock repos → real repos (PHASE 1.5).
      This prevents integration surprises.

📋 DAILY CHECKLIST (Day 1-5):

   Day 1 (Setup):
     - [ ] Add dependencies to pubspec.yaml
     - [ ] Create mock_data.dart (realistic seed data)
     - [ ] Create app_providers.dart (Riverpod DI container)
     - [ ] Create app_state.dart (AppState<T> wrapper)
     - [ ] Post: "✅ Setup complete: Riverpod + mock data ready"

   Day 2 (Navigation):
     - [ ] Setup go_router (8 routes)
     - [ ] Create BottomNavbar (role-filtered)
     - [ ] Create MainNavigationWrapper
     - [ ] Setup theme (colors + typography)
     - [ ] Create LoginScreen (demo users: admin/cashier/manager)
     - [ ] Post: "✅ Router + navbar + login done"

   Day 3 (Core Screens):
     - [ ] DashboardScreen (mock KPI cards)
     - [ ] SalesScreen (product grid + cart mock)
     - [ ] First unit test: Login → Dashboard → Sales navigation
     - [ ] Post: "✅ Dashboard + Sales done"
     - [ ] 🔔 SYNC CALL (30 min with backend team)

   Day 4 (Operations):
     - [ ] OrdersScreen (mock order list + status)
     - [ ] CustomersScreen (mock customer list + balance)
     - [ ] InventoryScreen (mock stock display)
     - [ ] Post: "✅ Orders + Customers + Inventory done"

   Day 5 (Final):
     - [ ] PaymentsScreen (mock payment form)
     - [ ] ReportsScreen (mock charts/reports)
     - [ ] SettingsScreen (navbar toggle + business config)
     - [ ] Shared widgets (ProductSearchDialog, CustomerSelector, etc.)
     - [ ] Final responsiveness check (portrait + landscape)
     - [ ] Post: "✅ All 8 screens complete + widgets done"

🔗 DEMO CREDENTIALS:
   Login username: admin
   Password: admin
   Role: Admin (all 8 tabs visible)

   Login username: cashier
   Password: cashier
   Role: Cashier (4 tabs: dashboard, sales, customers, payments)

   Login username: manager
   Password: manager
   Role: Manager (7 tabs: all except settings)

🔗 DELIVERABLE:
   ✅ Working UI skeleton (8 screens, all mock data)
   ✅ All screens render + navigate
   ✅ No real database calls
   ✅ No backend integration
   → Git commit: "PHASE 1: UI skeleton complete (mock layer)"

🎉 RESULT:
   After 5 days: ✅ UI skeleton 100% functional (mock)
   Waiting on: Backend team (parallel track, same 5 days)
   Next: PHASE 1.5 Integration (both merge)

REFERENCE DOCS:
   • PHASE_1_PARALLEL_BUILD_PACKAGE.md (your blueprint)
   • All code snippets included (copy-paste ready)
   • GELISTIRME_DURUM_RAPORU.md (what backend has completed)
   • Check Slack daily (backend team posts progress)

RIVERPOD GOLDEN RULE:
   "Providers follow AppState<T> pattern — no raw Futures in UI"

   ✅ CORRECT:
      final productListProvider = FutureProvider.autoDispose<List<ProductDTO>>((ref) async {
        final repo = ref.watch(mockProductRepositoryProvider);
        return await repo.getAllProducts();
      });

      ref.watch(productListProvider).when(
        loading: () => CircularProgressIndicator(),
        error: (err, stack) => Text('Error: $err'),
        data: (products) => ListView(...),
      );

   ❌ WRONG:
      final products = await database.query('products');  // Direct DB
      MathEngine.calculateTotal()  // Backend logic in UI

🚀 START NOW:
   1. Open PHASE_1_PARALLEL_BUILD_PACKAGE.md
   2. Add dependencies (Day 1 - Section 2.1)
   3. Create mock_data.dart (Day 1 - Section 5.1)
   4. Create app_providers.dart (Day 1 - Section 2.2)
   5. Post first commit by EOD: "PHASE 1: Setup ✅"

Questions? Ask now — don't guess!

═══════════════════════════════════════════════════════════════════════════════

UI_START

# ════════════════════════════════════════════════════════════════════════════════
# COMMAND 3: FOR PROJECT MANAGER / SCRUM MASTER
# ════════════════════════════════════════════════════════════════════════════════

cat << 'PM_START'

🔥 PROJECT MANAGER — PARALLEL TRACK ORCHESTRATION
═══════════════════════════════════════════════════════════════════════════════

Your mission: Keep both teams in sync (5-7 days parallel execution)

📋 OVERVIEW:
   • 2 independent tracks running simultaneously
   • 2 sync points (Day 3 & Day 5)
   • 0 blocking dependencies (except final merge)
   • Goal: MVP ready in 7-10 days

🎯 TRACK ASSIGNMENTS:

   TRACK 1 (Backend Architect):
   ├─ Implement PHASE 0 (foundation freeze)
   ├─ 8 sections (auth, state, error, transaction, rollback, schema, events, contract)
   ├─ Duration: 3-5 days
   └─ Deliverable: PHASE_0_FINAL_ENGINEERING_SPEC.md (Dart code)

   TRACK 2 (UI Engineer):
   ├─ Build PHASE 1 (UI skeleton + mock layer)
   ├─ 8 screens + router + navbar + widgets
   ├─ Duration: 3-5 days
   └─ Deliverable: Functioning UI (no backend calls)

⏱️  TIMELINE:

   DAY 1 (Parallel start):
   ├─ Backend: Auth contract ✅
   ├─ UI: Riverpod + mock data ✅
   └─ PM: Daily standup in Slack

   DAY 2 (Parallel):
   ├─ Backend: State pattern + Error model
   ├─ UI: Router + navbar + theme
   └─ PM: Check blockers

   DAY 3 (SYNC POINT — 30 min call):
   ├─ Backend: TransactionEngine pseudo → Dart (ready to show)
   ├─ UI: 3 screens navigating (dashboard, sales, login)
   ├─ SYNC CALL AGENDA:
   │  ├─ Backend shows: Auth + State + Error model
   │  ├─ UI shows: Navbar + 3 screens + mock data flow
   │  ├─ Decision: Any breaking changes? → NO → Continue
   │  └─ Confirm: Day 5 sync agenda
   └─ PM: Adjust schedule if needed

   DAY 4 (Parallel, final push):
   ├─ Backend: Rollback + schema + events
   ├─ UI: 7-8 screens + shared widgets
   └─ PM: Prepare integration checklist

   DAY 5 (SYNC POINT — full review):
   ├─ Backend: PHASE 0 COMPLETE ✅
   │  ├─ All 8 sections done
   │  ├─ Zero ambiguity
   │  ├─ Ready for UI to call real backend
   │  └─ Git: "PHASE 0: Foundation freeze complete"
   ├─ UI: PHASE 1 COMPLETE ✅
   │  ├─ All 8 screens functional
   │  ├─ Mock data layer working
   │  ├─ Ready to swap mock repos → real repos
   │  └─ Git: "PHASE 1: UI skeleton complete"
   ├─ FULL REVIEW CALL (60 min):
   │  ├─ Backend walkthrough (TransactionEngine + rollback)
   │  ├─ UI walkthrough (all screens + mock data flow)
   │  ├─ Identify integration points (DTO contracts)
   │  ├─ Decision: Ready for PHASE 1.5 integration? → YES
   │  └─ Confirm: PHASE 1.5 start (both teams together)
   └─ PM: Kick off integration next day

📊 DAILY TRACKING (5-day board):

   ┌──────────┬─────────┬─────────┬─────────┬─────────┬─────────┐
   │ Metric   │  Day 1  │  Day 2  │  Day 3  │  Day 4  │  Day 5  │
   ├──────────┼─────────┼─────────┼─────────┼─────────┼─────────┤
   │ Backend  │  1/8 ✓  │  2/8 ✓  │  4/8 ✓  │  6/8 ✓  │  8/8 ✓  │
   │ sections │         │         │  SYNC   │         │ FINAL   │
   ├──────────┼─────────┼─────────┼─────────┼─────────┼─────────┤
   │ UI       │  1/8 ✓  │  3/8 ✓  │  4/8 ✓  │  7/8 ✓  │  8/8 ✓  │
   │ screens  │         │         │  SYNC   │         │ FINAL   │
   ├──────────┼─────────┼─────────┼─────────┼─────────┼─────────┤
   │ Errors   │    0    │    0    │    0    │    0    │    0 ✓  │
   │ (compile)│         │         │         │         │ SUCCESS │
   ├──────────┼─────────┼─────────┼─────────┼─────────┼─────────┤
   │ Blockers │    0    │    0    │    0    │    0    │    0 ✓  │
   │          │         │         │         │         │ CLEAR   │
   └──────────┴─────────┴─────────┴─────────┴─────────┴─────────┘

🔔 YOUR DAILY RESPONSIBILITIES:

   MORNING (quick check):
   ├─ Read Slack updates from both tracks
   ├─ Check for blockers
   └─ Escalate if needed

   SYNC POINTS (Day 3 & Day 5):
   ├─ Host 30-60 min video call
   ├─ Both teams show live demos
   ├─ Identify integration risks
   └─ Confirm go/no-go to next phase

   EVENING (summary):
   ├─ Update project board
   ├─ Confirm tomorrow's plan
   └─ Post: "Day N complete: ✅ Backend X/8, ✅ UI Y/8"

⚠️  RISK FLAGS:

   🚩 Backend behind schedule?
      ├─ Root cause: Design scope creep
      ├─ Action: Defer to PHASE 2; freeze PHASE 0 as-is
      └─ Timeline: Still OK (just compacts design, not build)

   🚩 UI behind schedule?
      ├─ Root cause: Dependency blocker (mock data format?)
      ├─ Action: Backend helps mock layer ASAP
      └─ Timeline: Can compress Day 4-5

   🚩 Integration mismatch (Day 5)?
      ├─ Root cause: DTO contract differ than expected
      ├─ Action: Quick 2-hour fix (both teams sync)
      └─ Timeline: Push PHASE 1.5 start to Day 6 (acceptable)

🎯 SUCCESS METRICS:

   ✅ PHASE 0 (Backend):
      ✓ Zero ambiguity (all design decisions final)
      ✓ All 8 sections implemented (Dart code)
      ✓ Zero breaking changes after Day 5
      ✓ Ready for UI to call real backend

   ✅ PHASE 1 (UI):
      ✓ All 8 screens functional (mock layer)
      ✓ Responsive layout (portrait + landscape)
      ✓ No direct backend calls
      ✓ Ready to swap mock repos → real repos

   ✅ OVERALL:
      ✓ Zero compile errors (final)
      ✓ Zero blockers from dependencies
      ✓ Both teams confident in design
      ✓ PHASE 1.5 integration can start Day 6

📞 COMMS CHANNELS:

   SLACK (daily):
   ├─ #backend-phase0: Backend updates
   ├─ #ui-phase1: UI updates
   └─ #serenut-sync: Project-wide announcements

   SYNC CALLS:
   ├─ Day 3 (30 min): Mid-week check
   ├─ Day 5 (60 min): Final review + go/no-go integration
   └─ Day 6+ (if needed): Integration blockers

🎉 PHASE 1.5 INTEGRATION (Days 6-7):

   Both teams merge:
   ├─ Swap mock repos → real repositories
   ├─ Wire UI → real TransactionEngine
   ├─ Test end-to-end sale workflow
   ├─ Verify ledger + stock updates
   └─ RESULT: MVP READY ✅

📋 DAILY STANDUP TEMPLATE:

   PM Post (end of each day):
   """
   🚀 SERENUT POS — Day X Status
   
   Backend (Track 1):
   ✅ Completed: [auth/state/error/transaction/etc.]
   ⏳ In Progress: [next task]
   🚫 Blockers: None
   
   UI (Track 2):
   ✅ Completed: [screens/widgets/etc.]
   ⏳ In Progress: [next task]
   🚫 Blockers: None
   
   Overall: ✅ On track
   Next sync: Day 3 (30 min call)
   """

🚀 START NOW (TODAY):

   1. Send both engineers their START COMMAND
   2. Confirm receipt + start date
   3. Create daily standup thread in Slack
   4. Schedule sync calls (Day 3 & Day 5)
   5. Post project board (tracking metrics)
   6. Monitor for blockers

═══════════════════════════════════════════════════════════════════════════════

PM_START

echo "✅ All 3 commands ready. Copy-paste into Slack channels."

