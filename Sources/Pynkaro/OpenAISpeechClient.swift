import Foundation
import AVFoundation

enum OpenAISpeechSettings {
    static let defaultModel = "gpt-4o-mini-tts"
    static let defaultVoice = "onyx"
    static let defaultSpeed = 1.0
    static let defaultInstructions = """
        Fale em português brasileiro, com sotaque brasileiro neutro. Use uma voz masculina \
        jovem-adulta, entre 25 e 35 anos, com altura média a levemente aguda, timbre claro e \
        brilhante, tom suave, articulação nítida e pronúncia natural. Mantenha uma entrega \
        conversacional, amigável, inteligente, energética e levemente brincalhona, em ritmo \
        moderadamente rápido, com pausas curtas e naturais e entonação expressiva, porém \
        controlada. Soe espontâneo e acessível, como um assistente de tecnologia perspicaz \
        falando diretamente com uma pessoa. Evite voz grave ou retumbante, locução de rádio, \
        interpretação teatral, entusiasmo excessivo, voz soprosa, sensualidade, infantilidade, \
        ritmo robótico e sotaques regionais marcados. Mantenha o resultado natural, moderno, \
        conciso e responsivo.
        """

    static func model(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        nonEmptyValue("OPENAI_TTS_MODEL", environment: environment) ?? defaultModel
    }

    static func voice(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        nonEmptyValue("OPENAI_TTS_VOICE", environment: environment) ?? defaultVoice
    }

    static func speed(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Double {
        guard let raw = nonEmptyValue("OPENAI_TTS_SPEED", environment: environment),
              let value = Double(raw),
              (0.25...4.0).contains(value) else {
            return defaultSpeed
        }
        return value
    }

    static func instructions(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        nonEmptyValue("OPENAI_TTS_INSTRUCTIONS", environment: environment) ?? defaultInstructions
    }

    static func supportsInstructions(model: String) -> Bool {
        model.lowercased().hasPrefix("gpt-4o-mini-tts")
    }

    private static func nonEmptyValue(_ key: String,
                                      environment: [String: String]) -> String? {
        let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

enum OpenAISpeechError: LocalizedError, Equatable {
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "A OpenAI retornou uma resposta de voz inválida."
        case .httpError(let statusCode, let message):
            return "Erro da OpenAI (HTTP \(statusCode)): \(message)"
        case .emptyAudio:
            return "A OpenAI retornou um áudio vazio."
        }
    }
}

enum OpenAISpeechRequestBuilder {
    static func makeRequest(apiKey: String,
                            input: String,
                            model: String = OpenAISpeechSettings.defaultModel,
                            voice: String = OpenAISpeechSettings.defaultVoice,
                            speed: Double = OpenAISpeechSettings.defaultSpeed,
                            instructions: String = OpenAISpeechSettings.defaultInstructions) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "input": input,
            "voice": voice,
            "speed": speed,
            "response_format": "wav"
        ]
        if OpenAISpeechSettings.supportsInstructions(model: model) {
            body["instructions"] = instructions
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
}

final class OpenAISpeechClient {
    private let apiKey: String
    private let session: URLSession
    private let environment: [String: String]

    init(apiKey: String,
         session: URLSession = .shared,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.apiKey = apiKey
        self.session = session
        self.environment = environment
    }

    var modelID: String { OpenAISpeechSettings.model(environment: environment) }
    var voiceID: String { OpenAISpeechSettings.voice(environment: environment) }

    @discardableResult
    func synthesize(_ text: String,
                    completion: @escaping (Result<Data, Error>) -> Void) -> URLSessionDataTask {
        let request = OpenAISpeechRequestBuilder.makeRequest(
            apiKey: apiKey,
            input: text,
            model: modelID,
            voice: voiceID,
            speed: OpenAISpeechSettings.speed(environment: environment),
            instructions: OpenAISpeechSettings.instructions(environment: environment)
        )
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse, let data else {
                completion(.failure(OpenAISpeechError.invalidResponse))
                return
            }
            do {
                completion(.success(try Self.parseResponse(data: data,
                                                           statusCode: response.statusCode)))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
        return task
    }

    static func parseResponse(data: Data, statusCode: Int) throws -> Data {
        guard (200...299).contains(statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = json?["error"] as? [String: Any]
            let jsonMessage = error?["message"] as? String
            let textMessage = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = jsonMessage
                ?? ((textMessage?.isEmpty == false) ? textMessage : nil)
                ?? "Falha ao gerar o áudio."
            throw OpenAISpeechError.httpError(statusCode: statusCode, message: message)
        }
        guard !data.isEmpty else { throw OpenAISpeechError.emptyAudio }
        return data
    }
}

/// Converte texto em fala pela OpenAI e usa o macOS em qualquer falha.
final class OpenAISpeaker: NSObject, Speaking, AVAudioPlayerDelegate {
    var onMouthLevel: ((Int) -> Void)?

    private let client: OpenAISpeechClient
    private lazy var fallback = Speaker()
    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?
    private var meterTimer: Timer?
    private var currentText: String?

    init(apiKey: String) {
        client = OpenAISpeechClient(apiKey: apiKey)
        super.init()
        print("🗣️ Voz: OpenAI (modelo \(client.modelID), voz \(client.voiceID))")
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        self.completion = completion
        currentText = text
        client.synthesize(text) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let audioData):
                    self.play(audioData, originalText: text)
                case .failure(let error):
                    print("⚠️ OpenAI TTS: \(error.localizedDescription)")
                    self.fallbackSpeak(text)
                }
            }
        }
    }

    private func play(_ audioData: Data, originalText: String) {
        do {
            let player = try AVAudioPlayer(data: audioData)
            player.delegate = self
            player.isMeteringEnabled = true
            self.player = player
            guard player.play() else {
                throw OpenAISpeechError.invalidResponse
            }
            startMetering()
        } catch {
            print("⚠️ Falha ao tocar o áudio da OpenAI: \(error.localizedDescription)")
            fallbackSpeak(originalText)
        }
    }

    private func startMetering() {
        stopMetering()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) {
            [weak self] _ in
            guard let self, let player = self.player, player.isPlaying else { return }
            player.updateMeters()
            let db = player.averagePower(forChannel: 0)
            let level: Int
            if db > -18 {
                level = 2
            } else if db > -32 {
                level = 1
            } else {
                level = 0
            }
            self.onMouthLevel?(level)
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        onMouthLevel?(0)
    }

    private func fallbackSpeak(_ text: String) {
        stopMetering()
        player?.delegate = nil
        player?.stop()
        player = nil
        currentText = nil
        print("   Usando a voz do sistema como fallback.")
        fallback.onMouthLevel = onMouthLevel
        let callback = completion
        completion = nil
        fallback.speak(text) { callback?() }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopMetering()
        self.player = nil
        currentText = nil
        let callback = completion
        completion = nil
        callback?()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let detail = error?.localizedDescription ?? "erro desconhecido"
        print("⚠️ Erro ao decodificar o áudio da OpenAI: \(detail)")
        guard let currentText else {
            audioPlayerDidFinishPlaying(player, successfully: false)
            return
        }
        fallbackSpeak(currentText)
    }
}
