@testable import DockLogic
import XCTest

final class OrderingTests: XCTestCase {
    struct R { var key: String; var name: String; var status: DockStatus; var since: Double? = nil
        var place: [Int]; var pinned = false; var folder: String? = nil; var tag: DockTag? = nil
        var activity: Double? = nil }

    let rows = [
        R(key: "a", name: "zeta", status: .running, place: [0, 0]),
        R(key: "b", name: "Alpha", status: .idle, since: 100, place: [0, 1]),
        R(key: "c", name: "mid", status: .waiting, place: [1, 0]),
        R(key: "d", name: "beta", status: .unread, since: 200, place: [0, 2]),
    ]

    func keys(_ order: DockOrdering.Order, _ rows: [R], manual: [String] = []) -> [String] {
        DockOrdering.sorted(rows, order: order, manual: manual) {
            DockOrdering.Facts(key: $0.key, name: $0.name, status: $0.status,
                               since: $0.since.map(Date.init(timeIntervalSince1970:)), place: $0.place, pinned: $0.pinned,
                               activity: $0.activity.map(Date.init(timeIntervalSince1970:)))
        }.map(\.key)
    }

    func testAlphabeticalIgnoresCase() { XCTAssertEqual(keys(.alphabetical, rows), ["b", "d", "c", "a"]) }
    func testUrgencyNeedsYouFirstRecentIdleNextRunningLast() { XCTAssertEqual(keys(.urgency, rows), ["c", "d", "b", "a"]) }
    func testRunningFirst() { XCTAssertEqual(keys(.runningFirst, rows), ["a", "c", "d", "b"]) }
    func testTabOrder() { XCTAssertEqual(keys(.tabs, rows), ["a", "b", "d", "c"]) }

    func testPinnedAlwaysOnTop() {
        var r = rows
        r[0].pinned = true
        XCTAssertEqual(keys(.alphabetical, r).first, "a")
        XCTAssertEqual(keys(.urgency, r).first, "a")
    }

    func testManualOrderThenUnknownInTabOrder() {
        XCTAssertEqual(keys(.manual, rows, manual: ["c", "a"]), ["c", "a", "b", "d"])
    }

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
        var r = rows
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

    func testActivityDropRules() {
        XCTAssertEqual(DockOrdering.activityDrop(keyPinned: true, targetPinned: true), .reorder)
        XCTAssertEqual(DockOrdering.activityDrop(keyPinned: false, targetPinned: true), .pinAndReorder)
        XCTAssertEqual(DockOrdering.activityDrop(keyPinned: false, targetPinned: false), .ignore)
        XCTAssertEqual(DockOrdering.activityDrop(keyPinned: true, targetPinned: false), .ignore)
        XCTAssertEqual(DockOrdering.activityDrop(keyPinned: true, targetPinned: nil), .ignore)
    }

    func testMoveStartsFromWhatIsShown() {
        let moved = DockOrdering.move("d", before: "b", visible: ["b", "d", "c", "a"], manual: [])
        XCTAssertEqual(moved, ["d", "b", "c", "a"])
    }

    func testMoveToEndAndKeepsClosedRows() {
        let moved = DockOrdering.move("b", before: nil, visible: ["b", "c"], manual: ["x", "b", "c"])
        XCTAssertEqual(moved, ["c", "b", "x"])
    }

    func testGroupByFolderPinnedFirstOtherLast() {
        var r = rows
        r[0].folder = "work"; r[1].folder = "Play"; r[2].pinned = true; r[2].folder = "work"
        let g = DockOrdering.grouped(r, by: .folder, pinned: \.pinned, folder: \.folder, tag: \.tag)
        XCTAssertEqual(g.map(\.title), ["Pinned", "Play", "work", "Other"])
        XCTAssertEqual(g.map { $0.items.map(\.key) }, [["c"], ["b"], ["a"], ["d"]])
    }

    func testGroupByColourInTagOrder() {
        var r = rows
        r[0].tag = .blue; r[1].tag = .red
        let g = DockOrdering.grouped(r, by: .colour, pinned: \.pinned, folder: \.folder, tag: \.tag)
        XCTAssertEqual(g.map(\.title), ["Red", "Blue", "No colour"])
    }

    func testNoGroupingIsOneUntitledGroup() {
        let g = DockOrdering.grouped(rows, by: .none, pinned: \.pinned, folder: \.folder, tag: \.tag)
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].title, "")
    }

    func testFolderOfProject() {
        XCTAssertEqual(DockOrdering.folder(ofProject: "/Users/me/code/acme/api"), "acme")
        XCTAssertEqual(DockOrdering.folder(ofProject: "/Users/me/code/acme/api/.claude/worktrees/agent-1"), "acme")
        XCTAssertNil(DockOrdering.folder(ofProject: "/api"))
    }
}
