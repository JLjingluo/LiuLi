import XCTest
@testable import LogicCore

final class SSEParserTests: XCTestCase {

    func testDataLineExtraction() {
        XCTAssertEqual(SSEParser.payloadIfDataLine("data: hello"), "hello")
        XCTAssertEqual(SSEParser.payloadIfDataLine("data:nospace"), "nospace")
        XCTAssertNil(SSEParser.payloadIfDataLine("event: message"))
        XCTAssertNil(SSEParser.payloadIfDataLine(""))
    }

    func testCommentAndDone() {
        XCTAssertTrue(SSEParser.isComment(": keep-alive"))
        XCTAssertTrue(SSEParser.isDone("[DONE]"))
        XCTAssertTrue(SSEParser.isDone(" [DONE] "))
        XCTAssertFalse(SSEParser.isDone("{\"a\":1}"))
    }

    private func chunkJSON(content: String? = nil, reasoning: String? = nil) -> StreamChunk {
        var parts: [String] = []
        if let c = content { parts.append("\"content\":\(jsonEscaped(c))") }
        if let r = reasoning { parts.append("\"reasoning_content\":\(jsonEscaped(r))") }
        let json = """
        {"choices":[{"delta":{\(parts.joined(separator: ","))}}]}
        """
        return try! JSONDecoder().decode(StreamChunk.self, from: json.data(using: .utf8)!)
    }

    private func jsonEscaped(_ s: String) -> String {
        let data = try! JSONEncoder().encode(s)
        return String(data: data, encoding: .utf8)!
    }

    func testAccumulatorContentAndReasoning() {
        let acc = StreamAccumulator()
        acc.ingest(chunkJSON(content: "你"))
        acc.ingest(chunkJSON(content: "好"))
        acc.ingest(chunkJSON(reasoning: "思考"))
        XCTAssertTrue(acc.content == "你好")
        XCTAssertTrue(acc.reasoning == "思考")
        XCTAssertTrue(acc.usage == nil)
    }

    func testAccumulatorToolCallFragments() {
        // 模拟 tool_calls 分片：第一块带 id+name，后续块只带 arguments 增量
        let json1 = """
        {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"write_file","arguments":"{\\"pa"}}]}}]}
        """
        let json2 = """
        {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"th\\":\\"a.html\\",\\"content\\":\\"hi\\"}"}}]}}]}
        """
        let json3 = """
        {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}
        """
        let acc = StreamAccumulator()
        acc.ingest(try! JSONDecoder().decode(StreamChunk.self, from: json1.data(using: .utf8)!))
        acc.ingest(try! JSONDecoder().decode(StreamChunk.self, from: json2.data(using: .utf8)!))
        acc.ingest(try! JSONDecoder().decode(StreamChunk.self, from: json3.data(using: .utf8)!))

        XCTAssertTrue(acc.hasToolCalls)
        XCTAssertEqual(acc.finishReason, "tool_calls")
        let calls = acc.orderedToolCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].id, "call_1")
        XCTAssertEqual(calls[0].name, "write_file")
        XCTAssertEqual(calls[0].arguments, "{\"path\":\"a.html\",\"content\":\"hi\"}")

        // 参数可被 JSON 解析
        let obj = try! JSONSerialization.jsonObject(with: calls[0].arguments.data(using: .utf8)!) as! [String: Any]
        XCTAssertEqual(obj["path"] as? String, "a.html")
        XCTAssertEqual(obj["content"] as? String, "hi")
    }

    func testAccumulatorMultipleToolCalls() {
        let json = """
        {"choices":[{"delta":{"tool_calls":[
            {"index":0,"id":"a","type":"function","function":{"name":"list_files","arguments":"{}"}},
            {"index":1,"id":"b","type":"function","function":{"name":"read_file","arguments":"{}"}}
        ]}}]}
        """
        let acc = StreamAccumulator()
        acc.ingest(try! JSONDecoder().decode(StreamChunk.self, from: json.data(using: .utf8)!))
        let calls = acc.orderedToolCalls()
        XCTAssertEqual(calls.map { $0.id }, ["a", "b"])
        XCTAssertEqual(calls.map { $0.name }, ["list_files", "read_file"])
    }

    func testUsageChunk() {
        let json = """
        {"choices":[],"usage":{"prompt_tokens":120,"completion_tokens":45,"total_tokens":165}}
        """
        let acc = StreamAccumulator()
        acc.ingest(try! JSONDecoder().decode(StreamChunk.self, from: json.data(using: .utf8)!))
        XCTAssertEqual(acc.usage, UsageInfo(promptTokens: 120, completionTokens: 45))
    }

    func testErrorBodyDecoding() {
        let obj1 = try! JSONDecoder().decode(APIErrorBody.self, from: "{\"error\":{\"message\":\"Invalid API key\"}}".data(using: .utf8)!)
        XCTAssertEqual(obj1.message, "Invalid API key")
        let obj2 = try! JSONDecoder().decode(APIErrorBody.self, from: "{\"error\":\"余额不足\"}".data(using: .utf8)!)
        XCTAssertEqual(obj2.message, "余额不足")
        let obj3 = try! JSONDecoder().decode(APIErrorBody.self, from: "{\"message\":\"直接消息\"}".data(using: .utf8)!)
        XCTAssertEqual(obj3.message, "直接消息")
    }
}
