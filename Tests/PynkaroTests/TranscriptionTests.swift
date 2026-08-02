import Foundation
import XCTest
@testable import Pynkaro

final class OpenAITranscriptionTests: XCTestCase {
    func testTranscriptionModelComesFromEnvironmentWithStableDefault() {
        XCTAssertEqual(OpenAITranscriptionSettings.model(environment: [:]), "gpt-4o-transcribe")
        XCTAssertEqual(
            OpenAITranscriptionSettings.model(environment: ["OPENAI_TRANSCRIPTION_MODEL": "  "]),
            "gpt-4o-transcribe"
        )
        XCTAssertEqual(
            OpenAITranscriptionSettings.model(
                environment: ["OPENAI_TRANSCRIPTION_MODEL": "gpt-4o-mini-transcribe"]
            ),
            "gpt-4o-mini-transcribe"
        )
    }

    func testOpenAIIsOptionalWhenSelectingTranscriptionRoute() {
        XCTAssertEqual(TranscriptionRoute.preferred(openAIKey: nil), .macOS)
        XCTAssertEqual(TranscriptionRoute.preferred(openAIKey: ""), .macOS)
        XCTAssertEqual(TranscriptionRoute.preferred(openAIKey: "   "), .macOS)
        XCTAssertEqual(TranscriptionRoute.preferred(openAIKey: "sk-test"), .openAI)
    }

    func testMultipartRequestContainsAuthenticationFieldsAndAudio() throws {
        let request = OpenAITranscriptionRequestBuilder.makeRequest(
            apiKey: "sk-test",
            audioData: Data("AUDIO-CONTENT".utf8),
            model: "gpt-4o-mini-transcribe",
            filename: "pergunta.m4a",
            boundary: "TEST-BOUNDARY"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "multipart/form-data; boundary=TEST-BOUNDARY"
        )

        let body = try XCTUnwrap(request.httpBody)
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(text.contains("name=\"model\"\r\n\r\ngpt-4o-mini-transcribe"))
        XCTAssertTrue(text.contains("name=\"language\"\r\n\r\npt"))
        XCTAssertTrue(text.contains("name=\"response_format\"\r\n\r\njson"))
        XCTAssertTrue(text.contains("filename=\"pergunta.m4a\""))
        XCTAssertTrue(text.contains("Content-Type: audio/mp4"))
        XCTAssertTrue(text.contains("AUDIO-CONTENT"))
        XCTAssertTrue(text.hasSuffix("--TEST-BOUNDARY--\r\n"))
    }

    func testSuccessfulResponseReturnsTrimmedText() throws {
        let data = Data(#"{"text":"  Qual é a previsão?\n"}"#.utf8)
        let text = try OpenAITranscriptionClient.parseResponse(data: data, statusCode: 200)
        XCTAssertEqual(text, "Qual é a previsão?")
    }

    func testHTTPErrorPreservesStatusAndMessage() throws {
        let data = Data(#"{"error":{"message":"invalid key"}}"#.utf8)

        XCTAssertThrowsError(
            try OpenAITranscriptionClient.parseResponse(data: data, statusCode: 401)
        ) { error in
            XCTAssertEqual(
                error as? OpenAITranscriptionError,
                .httpError(statusCode: 401, message: "invalid key")
            )
        }
    }

    func testNonJSONHTTPErrorStillPreservesStatus() throws {
        XCTAssertThrowsError(
            try OpenAITranscriptionClient.parseResponse(
                data: Data("upstream unavailable".utf8),
                statusCode: 503
            )
        ) { error in
            XCTAssertEqual(
                error as? OpenAITranscriptionError,
                .httpError(statusCode: 503, message: "Falha ao transcrever o áudio.")
            )
        }
    }

    func testInvalidAndEmptyResponsesFail() throws {
        XCTAssertThrowsError(
            try OpenAITranscriptionClient.parseResponse(data: Data("not-json".utf8), statusCode: 200)
        ) { error in
            XCTAssertEqual(error as? OpenAITranscriptionError, .invalidResponse)
        }

        XCTAssertThrowsError(
            try OpenAITranscriptionClient.parseResponse(
                data: Data(#"{"text":"   "}"#.utf8),
                statusCode: 200
            )
        ) { error in
            XCTAssertEqual(error as? OpenAITranscriptionError, .emptyTranscription)
        }
    }
}

final class SpeechActivityDetectorTests: XCTestCase {
    func testNoSpeechTimesOutAfterSixSeconds() {
        var detector = SpeechActivityDetector()
        XCTAssertNil(detector.process(powerDB: -70, elapsed: 5.95))
        XCTAssertEqual(detector.process(powerDB: -70, elapsed: 6.0), .noSpeech)
    }

    func testSpeechFinishesAfterOnePointEightSecondsOfSilence() {
        var detector = SpeechActivityDetector()
        XCTAssertNil(detector.process(powerDB: -20, elapsed: 0.0))
        XCTAssertNil(detector.process(powerDB: -20, elapsed: 0.2))
        XCTAssertNil(detector.process(powerDB: -20, elapsed: 0.4))
        XCTAssertNil(detector.process(powerDB: -70, elapsed: 2.15))
        XCTAssertEqual(detector.process(powerDB: -70, elapsed: 2.2), .finish)
    }

    func testBriefNoiseDoesNotCountAsSpeech() {
        var detector = SpeechActivityDetector()
        XCTAssertNil(detector.process(powerDB: -20, elapsed: 0.0))
        XCTAssertNil(detector.process(powerDB: -70, elapsed: 0.1))
        XCTAssertEqual(detector.process(powerDB: -70, elapsed: 6.0), .noSpeech)
    }

    func testMaximumDurationFinishesAnActiveQuestion() {
        var detector = SpeechActivityDetector()
        XCTAssertNil(detector.process(powerDB: -20, elapsed: 0.0))
        XCTAssertNil(detector.process(powerDB: -20, elapsed: 0.2))
        XCTAssertEqual(detector.process(powerDB: -20, elapsed: 60.0), .finish)
    }
}
