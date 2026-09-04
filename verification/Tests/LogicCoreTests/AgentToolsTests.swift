import XCTest
@testable import LogicCore

final class AgentToolsTests: XCTestCase {

    var root: URL!
    var box: AgentToolBox!

    override func setUpWithError() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        root = tmp
        box = AgentToolBox(root: tmp)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: PathResolver

    func testResolveSimpleAndNested() {
        let a = PathResolver.resolve(root: root, relative: "index.html", blockedTopLevel: AgentToolBox.blockedTopLevel)
        XCTAssertEqual(a?.path, root.appendingPathComponent("index.html").path)

        let b = PathResolver.resolve(root: root, relative: "demo/sub/a.js", blockedTopLevel: AgentToolBox.blockedTopLevel)
        XCTAssertEqual(b?.path, root.appendingPathComponent("demo/sub/a.js").path)
    }

    func testResolveDotDotEscapeBlocked() {
        XCTAssertNil(PathResolver.resolve(root: root, relative: "../escape.txt", blockedTopLevel: []))
        XCTAssertNil(PathResolver.resolve(root: root, relative: "a/../../escape.txt", blockedTopLevel: []))
        XCTAssertNil(PathResolver.resolve(root: root, relative: "a/b/../../../c/../../../../d.txt", blockedTopLevel: []))
        // 内部 .. 是允许的（不越界）
        let ok = PathResolver.resolve(root: root, relative: "a/b/../c.txt", blockedTopLevel: [])
        XCTAssertEqual(ok?.path, root.appendingPathComponent("a/c.txt").path)
    }

    func testResolveAbsoluteAndBackslashTolerated() {
        let a = PathResolver.resolve(root: root, relative: "/etc/passwd", blockedTopLevel: [])
        XCTAssertEqual(a?.path, root.appendingPathComponent("etc/passwd").path)
        let b = PathResolver.resolve(root: root, relative: "dir\\file.txt", blockedTopLevel: [])
        XCTAssertEqual(b?.path, root.appendingPathComponent("dir/file.txt").path)
    }

    func testResolveBlockedTopLevel() {
        XCTAssertNil(PathResolver.resolve(root: root, relative: "Conversations/x.json", blockedTopLevel: ["Conversations"]))
        XCTAssertNil(PathResolver.resolve(root: root, relative: "conversations/x.json", blockedTopLevel: ["Conversations"]), "小写绕过也必须拦截")
    }

    func testResolveUnicodeAndEmpty() {
        let a = PathResolver.resolve(root: root, relative: "笔记/第一篇.md", blockedTopLevel: [])
        XCTAssertEqual(a?.path, root.appendingPathComponent("笔记/第一篇.md").path)
        let b = PathResolver.resolve(root: root, relative: "", blockedTopLevel: [])
        XCTAssertEqual(b?.path, root.path)
        let c = PathResolver.resolve(root: root, relative: "  ", blockedTopLevel: [])
        XCTAssertEqual(c?.path, root.path)
    }

    // MARK: 工具执行

    func testWriteReadRoundtrip() {
        let r = box.execute(name: "write_file", argumentsJSON: "{\"path\":\"hello.txt\",\"content\":\"你好，琉璃\"}")
        XCTAssertTrue(r.contains("已写入"), r)

        let read = box.execute(name: "read_file", argumentsJSON: "{\"path\":\"hello.txt\"}")
        XCTAssertEqual(read, "你好，琉璃")
    }

    func testWriteCreatesParentDirectories() {
        _ = box.execute(name: "write_file", argumentsJSON: "{\"path\":\"apps/game/index.html\",\"content\":\"<h1>hi</h1>\"}")
        let read = box.execute(name: "read_file", argumentsJSON: "{\"path\":\"apps/game/index.html\"}")
        XCTAssertEqual(read, "<h1>hi</h1>")
    }

    func testListFiles() {
        _ = box.execute(name: "write_file", argumentsJSON: "{\"path\":\"a.txt\",\"content\":\"1\"}")
        _ = box.execute(name: "write_file", argumentsJSON: "{\"path\":\"dir/b.txt\",\"content\":\"22\"}")
        let r = box.execute(name: "list_files", argumentsJSON: "{}")
        XCTAssertTrue(r.contains("a.txt"), r)
        XCTAssertTrue(r.contains("[目录] dir/"), r)

        let sub = box.execute(name: "list_files", argumentsJSON: "{\"path\":\"dir\"}")
        XCTAssertTrue(sub.contains("b.txt"), sub)
    }

    func testDeleteFile() {
        _ = box.execute(name: "write_file", argumentsJSON: "{\"path\":\"tmp/x.txt\",\"content\":\"\"}")
        let del = box.execute(name: "delete_file", argumentsJSON: "{\"path\":\"tmp/x.txt\"}")
        XCTAssertTrue(del.contains("已删除"), del)
        let read = box.execute(name: "read_file", argumentsJSON: "{\"path\":\"tmp/x.txt\"}")
        XCTAssertTrue(read.contains("不存在"), read)
    }

    func testReadMissingFile() {
        let r = box.execute(name: "read_file", argumentsJSON: "{\"path\":\"nope.txt\"}")
        XCTAssertTrue(r.contains("不存在"), r)
    }

    func testBlockedDirectoryAccess() {
        let r = box.execute(name: "write_file", argumentsJSON: "{\"path\":\"Conversations/evil.json\",\"content\":\"{}\"}")
        XCTAssertTrue(r.contains("非法"), r)
        let r2 = box.execute(name: "read_file", argumentsJSON: "{\"path\":\"Conversations/evil.json\"}")
        XCTAssertTrue(r2.contains("非法"), r2)
    }

    func testEscapeAttemptRejected() {
        let r = box.execute(name: "read_file", argumentsJSON: "{\"path\":\"../../etc/passwd\"}")
        XCTAssertTrue(r.contains("非法"), r)
    }

    func testLargeFileTruncated() {
        let big = String(repeating: "A", count: 150_000)
        _ = box.execute(name: "write_file", argumentsJSON: "{\"path\":\"big.txt\",\"content\":\"\(big)\"}")
        let r = box.execute(name: "read_file", argumentsJSON: "{\"path\":\"big.txt\"}")
        XCTAssertTrue(r.contains("已截断"), r)
        XCTAssertTrue(r.count < 150_000, "应被截断")
    }

    func testInvalidArgumentsJSON() {
        let r = box.execute(name: "read_file", argumentsJSON: "not json")
        XCTAssertTrue(r.contains("错误"), r)
    }

    func testUnknownTool() {
        let r = box.execute(name: "hack_the_world", argumentsJSON: "{}")
        XCTAssertTrue(r.contains("未知工具"), r)
    }

    func testToolSchemaShape() {
        let schemas = AgentToolBox.toolSchemas()
        XCTAssertEqual(schemas.count, 4)
        XCTAssertEqual(schemas.map { $0.function.name }, ["list_files", "read_file", "write_file", "delete_file"])
        // schema 本身可编码为 JSON（发给 API）
        let data = try! JSONEncoder().encode(schemas)
        XCTAssertTrue(String(data: data, encoding: .utf8)!.contains("list_files"))
    }
}
