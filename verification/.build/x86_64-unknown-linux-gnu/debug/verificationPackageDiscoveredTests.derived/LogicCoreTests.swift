import XCTest
@testable import LogicCoreTests

fileprivate extension AgentToolsTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__AgentToolsTests = [
        ("testBlockedDirectoryAccess", testBlockedDirectoryAccess),
        ("testDeleteFile", testDeleteFile),
        ("testEscapeAttemptRejected", testEscapeAttemptRejected),
        ("testInvalidArgumentsJSON", testInvalidArgumentsJSON),
        ("testLargeFileTruncated", testLargeFileTruncated),
        ("testListFiles", testListFiles),
        ("testReadMissingFile", testReadMissingFile),
        ("testResolveAbsoluteAndBackslashTolerated", testResolveAbsoluteAndBackslashTolerated),
        ("testResolveBlockedTopLevel", testResolveBlockedTopLevel),
        ("testResolveDotDotEscapeBlocked", testResolveDotDotEscapeBlocked),
        ("testResolveSimpleAndNested", testResolveSimpleAndNested),
        ("testResolveUnicodeAndEmpty", testResolveUnicodeAndEmpty),
        ("testToolSchemaShape", testToolSchemaShape),
        ("testUnknownTool", testUnknownTool),
        ("testWriteCreatesParentDirectories", testWriteCreatesParentDirectories),
        ("testWriteReadRoundtrip", testWriteReadRoundtrip)
    ]
}

fileprivate extension ContextBuilderTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__ContextBuilderTests = [
        ("testBasicLiteContext", testBasicLiteContext),
        ("testDeepKeepsAllImages", testDeepKeepsAllImages),
        ("testLiteStripsHistoryImagesButKeepsLast", testLiteStripsHistoryImagesButKeepsLast),
        ("testLiteWindowTrimsHistory", testLiteWindowTrimsHistory),
        ("testNoteMessagesExcluded", testNoteMessagesExcluded),
        ("testSanitizeDropsDanglingToolResult", testSanitizeDropsDanglingToolResult),
        ("testSanitizeKeepsCompleteToolCycle", testSanitizeKeepsCompleteToolCycle),
        ("testSanitizeRemovesDanglingToolCalls", testSanitizeRemovesDanglingToolCalls),
        ("testToolCallProtocolRoundTrip", testToolCallProtocolRoundTrip)
    ]
}

fileprivate extension MarkdownParserTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__MarkdownParserTests = [
        ("testCRLFLineEndings", testCRLFLineEndings),
        ("testCodeFence", testCodeFence),
        ("testDivider", testDivider),
        ("testEmptyInput", testEmptyInput),
        ("testHeadingLevel6Max", testHeadingLevel6Max),
        ("testHeadingLevels", testHeadingLevels),
        ("testOrderedListAndNesting", testOrderedListAndNesting),
        ("testParagraphMerging", testParagraphMerging),
        ("testQuoteBlockMergesLines", testQuoteBlockMergesLines),
        ("testTable", testTable),
        ("testTildeFence", testTildeFence),
        ("testUnclosedCodeFenceSwallowsToEOF", testUnclosedCodeFenceSwallowsToEOF),
        ("testUnorderedList", testUnorderedList)
    ]
}

fileprivate extension PathSecurityRegressionTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__PathSecurityRegressionTests = [
        ("testCaseInsensitiveBlacklistBypass", testCaseInsensitiveBlacklistBypass),
        ("testNullByteRejected", testNullByteRejected),
        ("testTildeRejected", testTildeRejected)
    ]
}

fileprivate extension SSEParserTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__SSEParserTests = [
        ("testAccumulatorContentAndReasoning", testAccumulatorContentAndReasoning),
        ("testAccumulatorMultipleToolCalls", testAccumulatorMultipleToolCalls),
        ("testAccumulatorToolCallFragments", testAccumulatorToolCallFragments),
        ("testCommentAndDone", testCommentAndDone),
        ("testDataLineExtraction", testDataLineExtraction),
        ("testErrorBodyDecoding", testErrorBodyDecoding),
        ("testUsageChunk", testUsageChunk)
    ]
}

fileprivate extension VisionCapabilityTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__VisionCapabilityTests = [
        ("testHintMentionsModelName", testHintMentionsModelName),
        ("testKnownTextOnlyModels", testKnownTextOnlyModels),
        ("testKnownVisionModels", testKnownVisionModels),
        ("testUnknownModelIsConservativelyTextOnly", testUnknownModelIsConservativelyTextOnly)
    ]
}
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
func __LogicCoreTests__allTests() -> [XCTestCaseEntry] {
    return [
        testCase(AgentToolsTests.__allTests__AgentToolsTests),
        testCase(ContextBuilderTests.__allTests__ContextBuilderTests),
        testCase(MarkdownParserTests.__allTests__MarkdownParserTests),
        testCase(PathSecurityRegressionTests.__allTests__PathSecurityRegressionTests),
        testCase(SSEParserTests.__allTests__SSEParserTests),
        testCase(VisionCapabilityTests.__allTests__VisionCapabilityTests)
    ]
}