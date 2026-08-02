import Foundation

enum TTSProvider: Equatable {
    case legacy
    case system
    case openAI
    case elevenLabs
    case auto
}

enum TTSRoute: Equatable {
    case system
    case openAI
    case elevenLabs
}

enum TTSProviderSettings {
    static func provider(environment: [String: String] = ProcessInfo.processInfo.environment)
        -> TTSProvider {
        guard let raw = environment["PYNKARO_TTS_PROVIDER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return .legacy
        }

        switch raw.lowercased() {
        case "system", "macos": return .system
        case "openai": return .openAI
        case "elevenlabs": return .elevenLabs
        case "auto": return .auto
        default:
            print("⚠️ PYNKARO_TTS_PROVIDER=\(raw) inválido; usando o comportamento legado.")
            return .legacy
        }
    }

    static func route(provider: TTSProvider,
                      openAIKey: String?,
                      elevenLabsKey: String?) -> TTSRoute {
        let hasOpenAI = hasValue(openAIKey)
        let hasElevenLabs = hasValue(elevenLabsKey)

        switch provider {
        case .legacy:
            return hasElevenLabs ? .elevenLabs : .system
        case .system:
            return .system
        case .openAI:
            return hasOpenAI ? .openAI : .system
        case .elevenLabs:
            return hasElevenLabs ? .elevenLabs : .system
        case .auto:
            if hasOpenAI { return .openAI }
            if hasElevenLabs { return .elevenLabs }
            return .system
        }
    }

    private static func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Resolve o provedor a cada resposta para perceber imediatamente chaves alteradas no Keychain.
final class SpeakerRouter: Speaking {
    var onMouthLevel: ((Int) -> Void)?

    private let provider: TTSProvider
    private lazy var systemSpeaker = Speaker()
    private var activeSpeaker: Speaking?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        provider = TTSProviderSettings.provider(environment: environment)
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        let openAIKey = Config.openAIKey
        let elevenLabsKey = Config.elevenLabsKey
        let route = TTSProviderSettings.route(
            provider: provider,
            openAIKey: openAIKey,
            elevenLabsKey: elevenLabsKey
        )

        let speaker: Speaking
        switch route {
        case .openAI:
            if let openAIKey {
                speaker = OpenAISpeaker(apiKey: openAIKey)
            } else {
                speaker = systemSpeaker
            }
        case .elevenLabs:
            if let elevenLabsKey {
                speaker = ElevenLabsSpeaker(apiKey: elevenLabsKey)
            } else {
                speaker = systemSpeaker
            }
        case .system:
            if provider == .openAI {
                print("⚠️ OpenAI escolhida para voz, mas OPENAI_API_KEY não está configurada.")
            } else if provider == .elevenLabs {
                print("⚠️ ElevenLabs escolhida para voz, mas ELEVENLABS_API_KEY não está configurada.")
            }
            speaker = systemSpeaker
        }

        activeSpeaker = speaker
        speaker.onMouthLevel = onMouthLevel
        speaker.speak(text) { [weak self] in
            self?.activeSpeaker = nil
            completion()
        }
    }
}
