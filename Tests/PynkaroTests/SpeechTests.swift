import Foundation
import XCTest
@testable import Pynkaro

final class TTSProviderSettingsTests: XCTestCase {
    func testMissingProviderPreservesLegacyRouting() {
        let provider = TTSProviderSettings.provider(environment: [:])

        XCTAssertEqual(provider, .legacy)
        XCTAssertEqual(
            TTSProviderSettings.route(
                provider: provider,
                openAIKey: "sk-openai",
                elevenLabsKey: "eleven-key"
            ),
            .elevenLabs
        )
        XCTAssertEqual(
            TTSProviderSettings.route(
                provider: provider,
                openAIKey: "sk-openai",
                elevenLabsKey: nil
            ),
            .system
        )
    }

    func testExplicitProvidersRequireTheirOwnKeys() {
        XCTAssertEqual(
            TTSProviderSettings.route(provider: .openAI,
                                      openAIKey: "sk-openai",
                                      elevenLabsKey: "eleven-key"),
            .openAI
        )
        XCTAssertEqual(
            TTSProviderSettings.route(provider: .openAI,
                                      openAIKey: "  ",
                                      elevenLabsKey: "eleven-key"),
            .system
        )
        XCTAssertEqual(
            TTSProviderSettings.route(provider: .elevenLabs,
                                      openAIKey: "sk-openai",
                                      elevenLabsKey: "eleven-key"),
            .elevenLabs
        )
        XCTAssertEqual(
            TTSProviderSettings.route(provider: .elevenLabs,
                                      openAIKey: "sk-openai",
                                      elevenLabsKey: nil),
            .system
        )
        XCTAssertEqual(
            TTSProviderSettings.route(provider: .system,
                                      openAIKey: "sk-openai",
                                      elevenLabsKey: "eleven-key"),
            .system
        )
    }

    func testAutoPrefersOpenAIThenElevenLabsThenSystem() {
        XCTAssertEqual(
            TTSProviderSettings.route(provider: .auto,
                                      openAIKey: "sk-openai",
                                      elevenLabsKey: "eleven-key"),
            .openAI
        )
        XCTAssertEqual(
            TTSProviderSettings.route(provider: .auto,
                                      openAIKey: nil,
                                      elevenLabsKey: "eleven-key"),
            .elevenLabs
        )
        XCTAssertEqual(
            TTSProviderSettings.route(provider: .auto,
                                      openAIKey: nil,
                                      elevenLabsKey: nil),
            .system
        )
    }

    func testProviderNamesAndInvalidFallback() {
        XCTAssertEqual(
            TTSProviderSettings.provider(environment: ["PYNKARO_TTS_PROVIDER": " openai "]),
            .openAI
        )
        XCTAssertEqual(
            TTSProviderSettings.provider(environment: ["PYNKARO_TTS_PROVIDER": "elevenlabs"]),
            .elevenLabs
        )
        XCTAssertEqual(
            TTSProviderSettings.provider(environment: ["PYNKARO_TTS_PROVIDER": "system"]),
            .system
        )
        XCTAssertEqual(
            TTSProviderSettings.provider(environment: ["PYNKARO_TTS_PROVIDER": "macos"]),
            .system
        )
        XCTAssertEqual(
            TTSProviderSettings.provider(environment: ["PYNKARO_TTS_PROVIDER": "auto"]),
            .auto
        )
        XCTAssertEqual(
            TTSProviderSettings.provider(environment: ["PYNKARO_TTS_PROVIDER": "desconhecido"]),
            .legacy
        )
    }
}

final class OpenAISpeechTests: XCTestCase {
    func testSettingsUseStableDefaultsAndEnvironmentOverrides() {
        XCTAssertEqual(OpenAISpeechSettings.model(environment: [:]), "gpt-4o-mini-tts")
        XCTAssertEqual(OpenAISpeechSettings.voice(environment: [:]), "onyx")
        XCTAssertEqual(OpenAISpeechSettings.speed(environment: [:]), 1.0)
        XCTAssertEqual(
            OpenAISpeechSettings.instructions(environment: [:]),
            OpenAISpeechSettings.defaultInstructions
        )

        let environment = [
            "OPENAI_TTS_MODEL": " gpt-4o-mini-tts-2025-12-15 ",
            "OPENAI_TTS_VOICE": " cedar ",
            "OPENAI_TTS_SPEED": "1.25",
            "OPENAI_TTS_INSTRUCTIONS": " Fale com energia. "
        ]
        XCTAssertEqual(OpenAISpeechSettings.model(environment: environment),
                       "gpt-4o-mini-tts-2025-12-15")
        XCTAssertEqual(OpenAISpeechSettings.voice(environment: environment), "cedar")
        XCTAssertEqual(OpenAISpeechSettings.speed(environment: environment), 1.25)
        XCTAssertEqual(OpenAISpeechSettings.instructions(environment: environment),
                       "Fale com energia.")
    }

    func testInvalidSpeedUsesDefault() {
        for invalid in ["texto", "0.24", "4.01", ""] {
            XCTAssertEqual(
                OpenAISpeechSettings.speed(environment: ["OPENAI_TTS_SPEED": invalid]),
                1.0
            )
        }
        XCTAssertEqual(OpenAISpeechSettings.speed(environment: ["OPENAI_TTS_SPEED": "0.25"]),
                       0.25)
        XCTAssertEqual(OpenAISpeechSettings.speed(environment: ["OPENAI_TTS_SPEED": "4"]),
                       4.0)
    }

    func testRequestContainsAuthenticationAndSpeechFields() throws {
        let request = OpenAISpeechRequestBuilder.makeRequest(
            apiKey: "sk-test",
            input: "Olá, mundo!",
            model: "gpt-4o-mini-tts",
            voice: "cedar",
            speed: 1.2,
            instructions: "Fale em português brasileiro."
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/speech")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 60)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let data = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(body["model"] as? String, "gpt-4o-mini-tts")
        XCTAssertEqual(body["input"] as? String, "Olá, mundo!")
        XCTAssertEqual(body["voice"] as? String, "cedar")
        XCTAssertEqual(body["speed"] as? Double, 1.2)
        XCTAssertEqual(body["response_format"] as? String, "wav")
        XCTAssertEqual(body["instructions"] as? String, "Fale em português brasileiro.")
    }

    func testLegacyModelsOmitUnsupportedInstructions() throws {
        for model in ["tts-1", "tts-1-hd"] {
            let request = OpenAISpeechRequestBuilder.makeRequest(
                apiKey: "sk-test",
                input: "Teste",
                model: model,
                instructions: "Não deve ser enviado"
            )
            let data = try XCTUnwrap(request.httpBody)
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            XCTAssertNil(body["instructions"])
        }
    }

    func testSuccessfulResponseReturnsAudioBytes() throws {
        let audio = Data([0x52, 0x49, 0x46, 0x46])
        XCTAssertEqual(
            try OpenAISpeechClient.parseResponse(data: audio, statusCode: 200),
            audio
        )
    }

    func testHTTPErrorUsesJSONOrPlainTextMessage() {
        XCTAssertThrowsError(
            try OpenAISpeechClient.parseResponse(
                data: Data(#"{"error":{"message":"invalid key"}}"#.utf8),
                statusCode: 401
            )
        ) { error in
            XCTAssertEqual(error as? OpenAISpeechError,
                           .httpError(statusCode: 401, message: "invalid key"))
        }

        XCTAssertThrowsError(
            try OpenAISpeechClient.parseResponse(
                data: Data("upstream unavailable".utf8),
                statusCode: 503
            )
        ) { error in
            XCTAssertEqual(error as? OpenAISpeechError,
                           .httpError(statusCode: 503, message: "upstream unavailable"))
        }
    }

    func testEmptyAndInvalidResponsesFail() {
        XCTAssertThrowsError(
            try OpenAISpeechClient.parseResponse(data: Data(), statusCode: 200)
        ) { error in
            XCTAssertEqual(error as? OpenAISpeechError, .emptyAudio)
        }

        XCTAssertThrowsError(
            try OpenAISpeechClient.parseResponse(data: Data(), statusCode: 0)
        ) { error in
            XCTAssertEqual(error as? OpenAISpeechError,
                           .httpError(statusCode: 0, message: "Falha ao gerar o áudio."))
        }
    }
}
