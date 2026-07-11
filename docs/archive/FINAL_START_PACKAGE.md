# 🚀 SERENUT POS — FINAL DUAL-TRACK START PACKAGE

**Date**: 20 Jun 2026  
**Status**: ✅ READY FOR DUAL-TRACK EXECUTION  
**Duration**: 5-7 days parallel execution  

---

# 📋 QUICK NAVIGATION

| Role | Read First | Duration | Output |
|------|-----------|----------|--------|
| **Backend / Architect** | PHASE_0_FINAL_ENGINEERING_SPEC.md | 3-5 days | ✅ Foundation frozen (auth, state, error, transaction, rollback) |
| **Frontend / UI Engineer** | PHASE_1_PARALLEL_BUILD_PACKAGE.md | 3-5 days | ✅ UI skeleton (navbar, screens, mock data) |
| **Project Manager** | THIS FILE | - | 📊 Sync point every 2 days |

---

# 🎯 EXECUTION MODEL: CONTROLLED HYBRID

```
┌────────────────────────────────────┐
│  TRACK 1: Backend Foundation       │
│  (Architect/Backend Engineer)      │
├────────────────────────────────────┤
│  ✅ Auth contract (local mock)     │
│  ✅ State pattern (AppState<T>)    │
│  ✅ Error model (exceptions)       │
│  ✅ TransactionEngine spec         │
│  ✅ Rollback rules                 │
│  ✅ SQLite schema final            │
│  ✅ Event system locked            │
│  Duration: 3-5 days                │
│  Output: PHASE_0_FINAL...spec.md   │
└────────────────────────────────────┘
         ↓ (SYNC POINT - Day 3)
         ↓ (Integration ready)
         ↓ (No breaking changes)
┌────────────────────────────────────┐
│  TRACK 2: UI Foundation            │
│  (UI/Frontend Engineer)            │
├────────────────────────────────────┤
│  ✅ Riverpod DI container          │
│  ✅ Bottom navbar (role-based)     │
│  ✅ 8 screens (mock data)          │
│  ✅ Router (go_router)             │
│  ✅ Shared widgets (mock)          │
│  ✅ Theme (colors + styling)       │
│  ✅ Mock repositories              │
│  Duration: 3-5 days                │
│  Output: PHASE_1_PARALLEL...pkg.md │
│  ⚠️  NO real backend calls yet     │
└────────────────────────────────────┘
         ↓ (BOTH TRACKS DONE)
         ↓ (Day 5-7)
┌────────────────────────────────────┐
│  PHASE 1.5: Integration            │
│  (Both tracks merge)               │
├────────────────────────────────────┤
│  ✅ Swap mock repos → real repos   │
│  ✅ Connect UI → TransactionEngine │
│  ✅ Real data flow (sales→ledger)  │
│  Duration: 2-3 days                │
│  Result: 🎉 MVP READY              │
└────────────────────────────────────┘
```

---

# 🎯 TRACK 1: BACKEND ARCHITECT

## ✅ Your Mission

Implement PHASE 0 foundation freeze:

```
📄 Source: PHASE_0_FINAL_ENGINEERING_SPEC.md

Tasks (in order):

1️⃣  Auth Contract
    ├─ Implement AuthService (local mock)
    ├─ AuthUser model + UserRole enum
    ├─ SharedPreferences storage
    └─ JWT bridge (for v2)

2️⃣  State Pattern Standard
    ├─ AppState<T> generic wrapper
    ├─ Integrate with Riverpod AsyncValue
    └─ Error propagation rules

3️⃣  Error Model
    ├─ AppException hierarchy
    ├─ Error codes (FINANCIAL_*, STOCK_*, PAYMENT_*)
    ├─ User-facing messages
    └─ Technical logging

4️⃣  TransactionEngine Pseudocode → Dart
    ├─ executeSaleTransaction()
    ├─ executeOrderDeliveryTransaction()
    ├─ executePaymentTransaction()
    └─ Atomic guarantees via RequiredDbExecutor

5️⃣  Rollback & Failure Strategy
    ├─ DB transaction wrapper
    ├─ All-or-nothing semantics
    ├─ Failure matrix (edge cases)
    └─ Recovery procedures

6️⃣  SQLite Schema Verification
    ├─ 18 tables DDL locked
    ├─ Soft delete enabled
    ├─ Ledger system ready
    └─ Indexes created

7️⃣  Event System Design
    ├─ 6 domain event types
    ├─ EventPublisher singleton
    ├─ Event handlers skeleton
    └─ Audit trail ready

8️⃣  UI↔Backend Contract
    └─ Data flow rules documented
```

## ⏱️ Timeline

```
Day 1: Auth + State Pattern (6-8 hours)
Day 2: Error Model + TransactionEngine pseudo (8-10 hours)
Day 3: Rollback strategy + Schema verification (6-8 hours)
  ↓ SYNC POINT (review with UI team)
Day 4-5: Event system + Contract finalization (4-6 hours)
```

## 📊 Success Criteria

- [ ] AuthService compiles (all methods working)
- [ ] AppState<T> wrapper used everywhere (no raw Future)
- [ ] Error codes enum complete (50+ codes locked)
- [ ] TransactionEngine pseudocode → Dart (all 3 methods)
- [ ] Rollback tested (simulated failures roll back correctly)
- [ ] Schema DDL verified (18 tables, all constraints)
- [ ] Event types immutable (no schema changes)
- [ ] Data flow diagram completed (UI→Controller→Service→Engine→DB)

## 🔗 Deliverables

**Output**: `PHASE_0_FINAL_ENGINEERING_SPEC.md` (updated with Dart implementations)

---

# 🎯 TRACK 2: UI ENGINEER

## ✅ Your Mission

Build UI skeleton with MOCK DATA:

```
📄 Source: PHASE_1_PARALLEL_BUILD_PACKAGE.md

Tasks (in order):

1️⃣  Day 1: Setup
    ├─ Add dependencies (riverpod, go_router, shared_preferences)
    ├─ Create mock_data.dart (fake products, customers, transactions)
    ├─ Create app_providers.dart (Riverpod DI container)
    └─ Create app_state.dart (AppState<T> wrapper)

2️⃣  Day 2: Navigation
    ├─ Setup go_router (8 routes)
    ├─ Create BottomNavbar (role-based tabs)
    ├─ Create MainNavigationWrapper
    └─ Setup theme (colors: green #2E7D32, yellow #FFD600, red, orange)

3️⃣  Day 3: Core Screens
    ├─ LoginScreen (mock auth: admin/cashier/manager)
    ├─ DashboardScreen (mock KPI cards)
    └─ SalesScreen (product grid + cart mock)

4️⃣  Day 4: Operations Screens
    ├─ OrdersScreen
    ├─ CustomersScreen
    └─ InventoryScreen

5️⃣  Day 5: Final Screens + Polish
    ├─ PaymentsScreen
    ├─ ReportsScreen
    ├─ SettingsScreen (navbar toggle)
    └─ Shared widgets (search, selectors, dialogs)
```

## ⏱️ Timeline

```
Day 1: Setup Riverpod + mock data (4-6 hours)
Day 2: Router + navbar + theme (4-6 hours)
Day 3: Login + Dashboard + Sales (6-8 hours)
Day 4: Orders + Customers + Inventory (6-8 hours)
Day 5: Payments + Reports + Settings + widgets (6-8 hours)
  ↓ SYNC POINT (review with backend team)
```

## 🚨 CRITICAL CONSTRAINTS

```
❌ ABSOLUTELY NOT ALLOWED (until PHASE 0 complete):

  ❌ NO real TransactionEngine calls
  ❌ NO SQLite queries
  ❌ NO payment processing logic
  ❌ NO stock calculations
  ❌ NO ledger writes
  ❌ NO event publishing
  ❌ NO MathEngine calls
  ❌ NO real balance updates

✅ WHAT YOU CAN DO:

  ✅ Use MockRepositories (return fake data + 300-500ms delay)
  ✅ Build UI forms (TextFields, buttons, selectors)
  ✅ Navigate between screens
  ✅ Display mock data
  ✅ Implement loading states
  ✅ Implement error handling (mock errors)
  ✅ Save UI preferences (Settings)
```

## 📊 Success Criteria

- [ ] No compile errors
- [ ] All 8 screens navigate
- [ ] Login → Dashboard flow works
- [ ] Navbar shows correct tabs for role
- [ ] Mock data loads with 300-500ms delay
- [ ] Dashboard KPI cards render
- [ ] Product/Customer lists populate
- [ ] Cart adds/removes items (state updates)
- [ ] Settings toggle saves navbar visibility
- [ ] No console errors (except info hints)
- [ ] Theme colors applied correctly
- [ ] Responsive layout (portrait + landscape)

## 🔗 Deliverables

**Output**: Functioning UI skeleton with mock data (testable, navigable, no backend)

---

# 🔄 SYNC POINTS (Day 3 & Day 5)

## Day 3 Sync (Mid-week)

**What**: Quick review of progress

**Backend presents**:
- Auth contract working
- AppState pattern implemented
- Initial error model

**UI presents**:
- Navbar rendering
- 3-4 screens navigating
- Mock data loading

**Decision**: Any breaking changes? No? → Continue.

## Day 5 Sync (Integration prep)

**What**: Full review before integration

**Backend presents**:
- ✅ PHASE 0 complete (all 8 sections locked)
- ✅ No outstanding design questions
- ✅ Ready for UI to call real backend

**UI presents**:
- ✅ All 8 screens complete with mock data
- ✅ All providers follow AppState<T> pattern
- ✅ Ready to swap mock repos → real repos

**Decision**: Ready for PHASE 1.5 integration? **YES** → BEGIN INTEGRATION

---

# 🔀 PHASE 1.5: INTEGRATION (After both tracks complete)

## Backend Integration Task

```
1. Swap mock repos → real repositories
2. Wire TransactionEngine provider
3. Implement real TransactionEngine methods
4. Test atomic transactions
5. Verify rollback on failures
```

## UI Integration Task

```
1. Replace MockProductRepository → real ProductRepository
2. Replace MockCustomerRepository → real CustomerRepository
3. Connect SalesScreen → real TransactionEngine
4. Connect PaymentsScreen → real TransactionEngine
5. Add real calculations (MathEngine feedback to UI)
6. Test end-to-end sale workflow
```

## Results

✅ **MVP READY** (after ~7-10 days total)

---

# 📞 COMMS PLAN

## Daily (15-min async updates)

Each track posts in Slack:

**Backend**:
```
Day 1: ✅ Auth contract working, starting State pattern
Day 2: ✅ State pattern + Error model done, TransactionEngine implementing
Day 3: ✅ TransactionEngine done, Rollback strategy in progress
```

**UI**:
```
Day 1: ✅ Riverpod setup done, mock data layer ready
Day 2: ✅ Router + navbar done, theme colors applied
Day 3: ✅ 3 screens done (Login, Dashboard, Sales)
```

## Sync Points (Day 3 & Day 5)

30-min Zoom call: Show live demos, discuss blockers

## Final Merge (Day 5+ integration)

Full team standup: Begin PHASE 1.5

---

# 🎓 REFERENCE DOCS

| Document | Purpose | Audience |
|----------|---------|----------|
| PHASE_0_FINAL_ENGINEERING_SPEC.md | Backend blueprint (locked) | Backend eng |
| PHASE_1_PARALLEL_BUILD_PACKAGE.md | UI blueprint (locked) | UI eng |
| GELISTIRME_DURUM_RAPORU.md | Status (what's done) | Everyone |
| TERMINOLOGY_GLOSSARY.md | Terms standardization | Everyone |
| STOCK_TIMING_RULES.md | Critical business rules | Backend eng |

---

# ⚠️ RISK MITIGATIONS

| Risk | Mitigation |
|------|-----------|
| UI builds features backend hasn't frozen yet | Sync points Day 3 & Day 5; mock data prevents integration). |
| Backend designs that break UI | All designs reviewed in PHASE 0; Sync point ensures alignment |
| Integration fails (data contract mismatch) | DTOs defined in PHASE 0; AppState wrapper standardizes UI |
| Unclear requirements | Pseudo-code in PHASE 0 = gospel; no changes without team sign-off |
| One track blocks the other | Completely parallel; mock data is UI's safety net |

---

# 🚀 START NOW

## For Backend Architect

```bash
👉 Open: PHASE_0_FINAL_ENGINEERING_SPEC.md
   ├─ Section 1: Auth Contract (start here)
   ├─ Section 2: DTOs (reference)
   ├─ Section 3: State Pattern
   ├─ Section 4: Transaction State Machine
   └─ ... (follow in order)

⏱️  Estimate: 3-5 days
📊 Output: PHASE_0_FINAL_ENGINEERING_SPEC.md (Dart implementations)
🎯 Success: All 8 sections locked, zero ambiguity
```

## For UI Engineer

```bash
👉 Open: PHASE_1_PARALLEL_BUILD_PACKAGE.md
   ├─ Section 1: Build Strategy
   ├─ Section 2: Riverpod Setup (start here)
   ├─ Section 3: Project Structure
   ├─ Section 4: Bottom Navbar
   └─ ... (follow in order)

⏱️  Estimate: 3-5 days
📊 Output: Functioning UI skeleton (8 screens, mock data, no backend calls)
🎯 Success: All 8 screens render, navigate, responsive
```

---

# ✅ FINAL CHECKLIST

Before either track starts:

- [ ] Both engineers have read their respective docs
- [ ] Both understand constraints + deliverables
- [ ] Both have slack channel for daily updates
- [ ] Both have scheduled sync points (Day 3 & 5)
- [ ] Architecture is FINAL (no more design decisions)
- [ ] Mock data seed = realistic business scenario
- [ ] Test credentials documented (admin/cashier/manager)
- [ ] Git branches created (backend feature branch, UI feature branch)

---

# 📊 METRIC TRACKING

**Day 1-5 Status Board**:

| Metric | Target | Day 1 | Day 2 | Day 3 | Day 4 | Day 5 |
|--------|--------|-------|-------|-------|-------|-------|
| Backend sections done | 8/8 | 1/8 | 2/8 | 4/8 | 6/8 | 8/8 ✅ |
| UI screens done | 8/8 | 1/8 | 3/8 | 4/8 | 7/8 | 8/8 ✅ |
| Compilation errors | 0 | - | - | - | - | 0 ✅ |
| Blockers | 0 | - | - | 0 | - | 0 ✅ |

---

# 🎉 DONE

Both tracks complete → PHASE 1.5 integration → MVP ready

**Estimated Total**: 7-10 days to MVP

---

**Status**: 🟢 READY TO START  
**Authority**: Engineering Review  
**Next**: Both tracks begin simultaneously (TODAY)  

🚀 **GO BUILD!**
