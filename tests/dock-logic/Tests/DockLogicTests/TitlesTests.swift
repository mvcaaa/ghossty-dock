@testable import DockLogic
import XCTest

final class TitlesTests: XCTestCase {
    func lines(_ json: String...) -> Data { Data((json.joined(separator: "\n") + "\n").utf8) }

    func testReadsEachKindOfName() {
        var t = DockTitles()
        t.take(lines(#"{"type":"user","message":"hi"}"#,
                     #"{"type":"ai-title","aiTitle":"Fix the build"}"#,
                     #"{"type":"agent-name","agentName":"staging-backups"}"#,
                     #"{"type":"custom-title","customTitle":"follow-renamed"}"#))
        XCTAssertEqual(t.ai, "Fix the build")
        XCTAssertEqual(t.agent, "staging-backups")
        XCTAssertEqual(t.custom, "follow-renamed")
        XCTAssertEqual(t.all, ["follow-renamed", "staging-backups", "Fix the build"])
    }

    func testChosenPrefersCustomThenAgentNeverAI() {
        XCTAssertEqual(DockTitles(custom: "c", agent: "a", ai: "x").chosen, "c")
        XCTAssertEqual(DockTitles(agent: "a", ai: "x").chosen, "a")
        XCTAssertNil(DockTitles(ai: "x").chosen)
    }

    func testLaterRenameWins() {
        var t = DockTitles()
        t.take(lines(#"{"type":"custom-title","customTitle":"one"}"#,
                     #"{"type":"custom-title","customTitle":"two"}"#))
        XCTAssertEqual(t.custom, "two")
    }

    func testPartialLineWaitsForTheRest() {
        var t = DockTitles()
        let whole = #"{"type":"custom-title","customTitle":"done"}"# + "\n"
        let partial = #"{"type":"custom-title","custom"#
        t.take(Data((whole + partial).utf8))
        XCTAssertEqual(t.custom, "done")
        XCTAssertEqual(t.offset, UInt64(whole.utf8.count))
    }

    func testNoNewlineReadsNothing() {
        var t = DockTitles()
        t.take(Data(#"{"type":"custom-title","customTitle":"x"}"#.utf8))
        XCTAssertNil(t.custom)
        XCTAssertEqual(t.offset, 0)
    }

    func testSkipsLongLinesAndBadJSON() {
        var t = DockTitles()
        let long = #"{"type":"custom-title","customTitle":""# + String(repeating: "x", count: 5000) + #""}"#
        t.take(lines(long, #"{"type":"custom-title", broken"#, #"{"type":"agent-name","agentName":"ok"}"#))
        XCTAssertNil(t.custom)
        XCTAssertEqual(t.agent, "ok")
    }

    func testReadsTheFileAsItGrowsAndStartsOverWhenItShrinks() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(DockTitles.read(url.path, after: nil))

        try lines(#"{"type":"custom-title","customTitle":"first"}"#).write(to: url)
        let t1 = try XCTUnwrap(DockTitles.read(url.path, after: nil))
        XCTAssertEqual(t1.custom, "first")

        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: lines(#"{"type":"agent-name","agentName":"bg"}"#))
        try h.close()
        let t2 = try XCTUnwrap(DockTitles.read(url.path, after: t1))
        XCTAssertEqual(t2.custom, "first")
        XCTAssertEqual(t2.agent, "bg")

        try lines(#"{"type":"ai-title","aiTitle":"new"}"#).write(to: url)
        let t3 = try XCTUnwrap(DockTitles.read(url.path, after: t2))
        XCTAssertNil(t3.custom)
        XCTAssertEqual(t3.ai, "new")
    }

    func testCleanTitleDropsClaudeStatusGlyphs() {
        XCTAssertEqual(dockCleanTitle("✳ test-follow"), "test-follow")
        XCTAssertEqual(dockCleanTitle("⠂ staging"), "staging")
        XCTAssertEqual(dockCleanTitle("#staging-backups pipeline error"), "staging-backups pipeline error")
        XCTAssertEqual(dockCleanTitle("~/work/tasks"), "~/work/tasks")
        XCTAssertEqual(dockCleanTitle("✳ "), "")
    }

    func testShownMatchesAnyNameCleaned() {
        let t = DockTitles(agent: "#staging-backups pipeline error", ai: "Fix it")
        XCTAssertTrue(t.shown(in: "staging-backups pipeline error"))
        XCTAssertTrue(t.shown(in: "Fix it"))
        XCTAssertFalse(t.shown(in: "test-follow"))
        XCTAssertFalse(t.shown(in: ""))
    }

    func testOwnNamePrefersTranscriptThenFocusedTitleThenHook() {
        let named = DockTitles(custom: "follow-renamed")
        XCTAssertEqual(DockTitles.ownName(named, title: "other", focused: true, fallback: "tasks"), "follow-renamed")
        XCTAssertEqual(DockTitles.ownName(nil, title: "test-follow", focused: true, fallback: "tasks"), "test-follow")
        XCTAssertEqual(DockTitles.ownName(DockTitles(ai: "x"), title: "test-follow", focused: true, fallback: "tasks"),
                       "test-follow")
    }

    func testOwnNameIgnoresUnfocusedAndGenericTitles() {
        XCTAssertEqual(DockTitles.ownName(nil, title: "test-follow", focused: false, fallback: "tasks"), "tasks")
        XCTAssertEqual(DockTitles.ownName(nil, title: "Ghostty", focused: true, fallback: "tasks"), "tasks")
        XCTAssertEqual(DockTitles.ownName(nil, title: "Claude Code", focused: true, fallback: "tasks"), "tasks")
        XCTAssertEqual(DockTitles.ownName(nil, title: "", focused: true, fallback: "tasks"), "tasks")
    }
}
