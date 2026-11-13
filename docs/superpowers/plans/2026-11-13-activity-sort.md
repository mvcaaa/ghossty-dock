# Activity Sort Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Sort option "Activity": pinned rows (drag order) → shells → needs you → running (latest activity first) → finished/idle (latest stop first), frozen while the pointer is over the sidebar.

**Architecture:** Pure ordering in `DockOrdering` (Foundation only, unit-tested in `tests/dock-logic`); `DockSessions` feeds it the hook's `updated` time and applies a held order while hovered; drag rules live in `DockSessions.move`.

**Tech Stack:** Swift 6 / SwiftUI, XCTest via `swift test --package-path tests/dock-logic`.

**Spec:** `docs/superpowers/specs/2026-11-13-activity-sort-design.md`

## Global Constraints

- Edit sources in `vendor/ghostty/macos/Sources/Features/Dock/` (not committed); before every commit run `scripts/build-terminal.sh --save-patch` and commit `patches/ghostty-dock.patch` alongside the tests.
- Other sort modes keep today's behaviour exactly (existing `OrderingTests` stay green unchanged).
- Branch `activity-sort`. Commits are signed by git config — never pass signing flags.
- Comments only where they clarify current behaviour; match the file's existing plain-English doc-comment style.

## Review Focus

1. Two running rows with equal or missing `updated` must not flip each round → tie-break on `place` (Task 1 test `testActivityTiesKeepTabOrder`).
2. A row whose session ends while hovered (row disappears) or a new tab appearing while hovered → held order drops/appends without crashing (Task 1 test `testHeldDropsGoneAppendsNew`).
3. Pinned row that is also a shell or waiting stays in the pinned block, not its status section (Task 1 test `testActivityPinnedBeatStatus`).
4. Dropping onto the bottom "end" zone (`target == nil`) in Activity mode does nothing and does not switch the sort to manual (Task 3 test `testActivityDropRules`).
5. Old session files without `updated` decode fine (field optional; Task 2 step 1).

---

### Task 1: Activity ordering and held order in `DockOrdering`

**Files:**
- Modify: `vendor/ghostty/macos/Sources/Features/Dock/DockOrdering.swift` (`Order`, `Facts`, `sorted`, new `held`)
- Test: `tests/dock-logic/Tests/DockLogicTests/OrderingTests.swift`

**Interfaces:**
- Produces: `DockOrdering.Order.activity` (label `"Activity: shells, needs you, then most recently active"`); `Facts.activity: Date? = nil` (new last stored property with default, so existing initialisers compile); `static func held<T>(_ items: [T], previous: [String], key: (T) -> String) -> [T]`.

- [ ] **Step 1: Write failing tests.** Extend the test struct `R` with `var activity: Double? = nil` and pass `activity: $0.activity.map(Date.init(timeIntervalSince1970:))` in `keys(...)`. Add:

```swift
func testActivityOrder() {
    let r = [
        R(key: "run-old", name: "a", status: .running, since: 10, place: [0, 0], activity: 50),
        R(key: "idle-old", name: "b", status: .idle, since: 100, place: [0, 1]),
        R(key: "sh", name: "c", status: .shell, place: [0, 2]),
        R(key: "ask", name: "d", status: .waiting, since: 5, place: [0, 3]),
        R(key: "run-new", name: "e", status: .running, since: 20, place: [0, 4], activity: 90),
        R(key: "done-new", name: "f", status: .unread, since: 300, place: [0, 5]),
    ]
    XCTAssertEqual(keys(.activity, r), ["sh", "ask", "run-new", "run-old", "done-new", "idle-old"])
}
func testActivityFallsBackToSince() {
    let r = [R(key: "x", name: "x", status: .running, since: 10, place: [0, 0]),
             R(key: "y", name: "y", status: .running, since: 30, place: [0, 1])]
    XCTAssertEqual(keys(.activity, r), ["y", "x"])
}
func testActivityTiesKeepTabOrder() {
    let r = [R(key: "x", name: "x", status: .running, place: [0, 1], activity: 5),
             R(key: "y", name: "y", status: .running, place: [0, 0], activity: 5)]
    XCTAssertEqual(keys(.activity, r), ["y", "x"])
}
func testActivityPinnedInManualOrderBeatStatus() {
    var r = rows                       // a running, b idle, c waiting, d unread
    r[1].pinned = true; r[3].pinned = true
    XCTAssertEqual(Array(keys(.activity, r, manual: ["d", "b"]).prefix(2)), ["d", "b"])
}
func testActivityPinnedBeatStatus() {
    let r = [R(key: "sh", name: "s", status: .shell, place: [0, 0]),
             R(key: "p", name: "p", status: .idle, place: [0, 1], pinned: true)]
    XCTAssertEqual(keys(.activity, r), ["p", "sh"])
}
func testHeldKeepsPreviousOrder() {
    XCTAssertEqual(DockOrdering.held(["a", "b", "c"], previous: ["c", "a", "b"], key: { $0 }), ["c", "a", "b"])
}
func testHeldDropsGoneAppendsNew() {
    XCTAssertEqual(DockOrdering.held(["a", "n", "c"], previous: ["c", "gone", "a"], key: { $0 }), ["c", "a", "n"])
}
```

(`R`'s memberwise init order: add `activity` after `tag`, and use labelled args as above — reorder the `R(...)` labels in the new tests to match the struct's property order if the compiler requires it.)

- [ ] **Step 2: Run, expect compile failure** (`activity` / `.activity` / `held` missing): `swift test --package-path tests/dock-logic --filter OrderingTests`

- [ ] **Step 3: Implement.** In `sorted`, the `.activity` case: if both pinned → compare `manualIndex` (known before unknown), then `place`. Otherwise section = shell 0, waiting 1, running 2, unread/idle 3; within running compare `(activity ?? since)` descending; within unread/idle compare `since` descending; nil dates sort after non-nil; then `place`. The existing `if a.pinned != b.pinned { return a.pinned }` line stays first. `held`: items whose key is in `previous`, in `previous` order, then the rest in their given order.

- [ ] **Step 4: Run** `swift test --package-path tests/dock-logic` — all tests pass, including the untouched existing ones.

- [ ] **Step 5: Commit** — `scripts/build-terminal.sh --save-patch`, then `git add patches/ghostty-dock.patch tests/dock-logic && git commit -m "Activity sort: shells, needs you, then most recently active"`.

### Task 2: Feed activity and hold the order while hovered

**Files:**
- Modify: `vendor/ghostty/macos/Sources/Features/Dock/DockSessions.swift` — `Session` (~l.721), `Row` (~l.20), `best` tuple and its two assignments (~l.1063–1088), `Row(...)` build (~l.1113), the `DockOrdering.sorted` call (~l.1154)
- Modify: `vendor/ghostty/macos/Sources/Features/Dock/DockSidebarView.swift` — the sidebar `ScrollView` (~l.89)

**Interfaces:**
- Consumes: Task 1's `Facts.activity`, `Order.activity`, `held`.
- Produces: `DockSessions.holdOrder: Bool` (settable from the view; `didSet` to `false` calls `refresh()`).

- [ ] **Step 1:** `Session` gains `var updated: Int?`; the `best` tuple gains `updated: Int?` (filled from `s.updated` in both assignments); `Row` gains `var activity: Date?`, set from it. Do **not** add `activity` to `Row.==` (it changes on every tool call; order changes are already caught by `flat != rows`).
- [ ] **Step 2:** Pass `activity: r.activity` into `Facts` in the `sorted` call. Right after it: `if holdOrder, DockSettings.order == .activity { built = DockOrdering.held(built, previous: heldKeys, key: \.key) }`, then `heldKeys = built.map(\.key)` (private `[String]`).
- [ ] **Step 3:** In `DockSidebarView`, on the `ScrollView`: `.onHover { model.holdOrder = $0 }`.
- [ ] **Step 4: Build** `scripts/build-terminal.sh --no-open` — succeeds; `swift test --package-path tests/dock-logic` still green.
- [ ] **Step 5: Commit** — `--save-patch`, then `git add patches/ghostty-dock.patch && git commit -m "Activity sort follows each tool call, holds still under the pointer"`.

### Task 3: Drag rules in Activity mode

**Files:**
- Modify: `vendor/ghostty/macos/Sources/Features/Dock/DockOrdering.swift` (new `activityDrop`)
- Modify: `vendor/ghostty/macos/Sources/Features/Dock/DockSessions.swift` — `move(_:before:)` (~l.1490)
- Test: `tests/dock-logic/Tests/DockLogicTests/OrderingTests.swift`

**Interfaces:**
- Produces: `enum DockOrdering.Drop { case reorder, pinAndReorder, ignore }`; `static func activityDrop(keyPinned: Bool, targetPinned: Bool?) -> Drop` (`targetPinned == nil` means dropped at the end).

- [ ] **Step 1: Failing test**

```swift
func testActivityDropRules() {
    XCTAssertEqual(DockOrdering.activityDrop(keyPinned: true, targetPinned: true), .reorder)
    XCTAssertEqual(DockOrdering.activityDrop(keyPinned: false, targetPinned: true), .pinAndReorder)
    XCTAssertEqual(DockOrdering.activityDrop(keyPinned: false, targetPinned: false), .ignore)
    XCTAssertEqual(DockOrdering.activityDrop(keyPinned: true, targetPinned: false), .ignore)
    XCTAssertEqual(DockOrdering.activityDrop(keyPinned: true, targetPinned: nil), .ignore)
}
```

- [ ] **Step 2: Run, expect failure** (`activityDrop` missing).
- [ ] **Step 3: Implement** `activityDrop`, then in `move`: when `DockSettings.order == .activity`, look up both rows' `pinned`, switch on `activityDrop`: `.ignore` → return; `.pinAndReorder` → `setMeta(row) { $0.pinned = true }` then fall through; both non-ignore cases write the manual list as today but **skip** the switch to `.manual`. Other modes: unchanged.
- [ ] **Step 4: Run** tests green; `scripts/build-terminal.sh --no-open` succeeds.
- [ ] **Step 5: Commit** — `--save-patch`; `git add patches/ghostty-dock.patch tests/dock-logic && git commit -m "Activity sort: drag reorders pins, drop into pins to pin"`.

### Task 4: Hand check in the running app

- [ ] Launch `~/Applications/Ghostty Dock.app` (base build), Settings → Sort → Activity.
- [ ] Two Claude tabs: prompt one, its row rises above the other running row; with the pointer over the sidebar nothing moves until it leaves.
- [ ] Pin two rows, drag to swap them; drag an unpinned row onto a pinned one → it pins there; drop at the bottom → nothing, Sort still shows Activity.
- [ ] Shell tab sits under the pins, above everything else.
