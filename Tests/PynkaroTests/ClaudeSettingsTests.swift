import XCTest
@testable import Pynkaro

final class ClaudeEffortSettingsTests: XCTestCase {
    func testSonnetAndOpusAcceptDocumentedEffortLevels() {
        XCTAssertEqual(
            ClaudeEffortSettings.resolve(
                model: "claude-sonnet-5",
                environment: ["PYNKARO_CLAUDE_EFFORT": "low"]
            ),
            "low"
        )
        XCTAssertEqual(
            ClaudeEffortSettings.resolve(
                model: "claude-opus-5",
                environment: ["PYNKARO_CLAUDE_EFFORT": "max"]
            ),
            "max"
        )
    }

    func testHaikuIgnoresEffortBecauseAPIModelDoesNotSupportIt() {
        XCTAssertNil(
            ClaudeEffortSettings.resolve(
                model: "claude-haiku-4-5",
                environment: ["PYNKARO_CLAUDE_EFFORT": "low"]
            )
        )
    }

    func testMissingAndInvalidEffortPreserveAPIDefault() {
        XCTAssertNil(ClaudeEffortSettings.resolve(model: "claude-sonnet-5", environment: [:]))
        XCTAssertNil(
            ClaudeEffortSettings.resolve(
                model: "claude-sonnet-5",
                environment: ["PYNKARO_CLAUDE_EFFORT": "turbo"]
            )
        )
    }
}
