import Foundation
import AVFoundation

enum SpeechActivityDecision: Equatable {
    case finish
    case noSpeech
}

/// Decide quando uma gravação deve terminar a partir do nível médio do áudio.
/// Separado do AVAudioRecorder para que os limites possam ser testados sem microfone.
struct SpeechActivityDetector {
    let initialTimeout: TimeInterval
    let silenceDuration: TimeInterval
    let maximumDuration: TimeInterval
    let speechThresholdDB: Float
    let minimumSpeechDuration: TimeInterval

    private var candidateSpeechStartedAt: TimeInterval?
    private var lastSpeechAt: TimeInterval?

    init(initialTimeout: TimeInterval = 6.0,
         silenceDuration: TimeInterval = 1.8,
         maximumDuration: TimeInterval = 60.0,
         speechThresholdDB: Float = -35.0,
         minimumSpeechDuration: TimeInterval = 0.15) {
        self.initialTimeout = initialTimeout
        self.silenceDuration = silenceDuration
        self.maximumDuration = maximumDuration
        self.speechThresholdDB = speechThresholdDB
        self.minimumSpeechDuration = minimumSpeechDuration
    }

    mutating func process(powerDB: Float, elapsed: TimeInterval) -> SpeechActivityDecision? {
        if elapsed >= maximumDuration {
            return lastSpeechAt == nil ? .noSpeech : .finish
        }

        if powerDB >= speechThresholdDB {
            if lastSpeechAt != nil {
                lastSpeechAt = elapsed
            } else if let startedAt = candidateSpeechStartedAt {
                if elapsed - startedAt >= minimumSpeechDuration {
                    lastSpeechAt = elapsed
                }
            } else {
                candidateSpeechStartedAt = elapsed
            }
        } else {
            candidateSpeechStartedAt = nil
        }

        if let lastSpeechAt, elapsed - lastSpeechAt >= silenceDuration {
            return .finish
        }
        if lastSpeechAt == nil && elapsed >= initialTimeout {
            return .noSpeech
        }
        return nil
    }
}

enum QuestionRecorderError: LocalizedError {
    case couldNotStart
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .couldNotStart:
            return "Não foi possível iniciar a gravação da pergunta."
        case .encodingFailed:
            return "Não foi possível salvar o áudio da pergunta."
        }
    }
}

/// Grava uma pergunta em M4A e encerra por silêncio, timeout ou duração máxima.
/// Um URL não nulo transfere ao chamador a responsabilidade de apagar o arquivo.
final class QuestionRecorder: NSObject, AVAudioRecorderDelegate {
    typealias Completion = (Result<URL?, Error>) -> Void

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var completion: Completion?
    private var outputURL: URL?
    private var startedAt: Date?
    private var activityDetector = SpeechActivityDetector()

    func start(completion: @escaping Completion) throws {
        cancel()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pynkaro-question-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            try? FileManager.default.removeItem(at: url)
            throw QuestionRecorderError.couldNotStart
        }

        self.recorder = recorder
        self.outputURL = url
        self.completion = completion
        self.startedAt = Date()
        self.activityDetector = SpeechActivityDetector()

        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.sampleAudioLevel()
        }
    }

    func cancel() {
        meterTimer?.invalidate()
        meterTimer = nil
        completion = nil

        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        startedAt = nil

        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        outputURL = nil
    }

    private func sampleAudioLevel() {
        guard let recorder, let startedAt else { return }
        recorder.updateMeters()
        let elapsed = Date().timeIntervalSince(startedAt)
        guard let decision = activityDetector.process(
            powerDB: recorder.averagePower(forChannel: 0),
            elapsed: elapsed
        ) else { return }

        switch decision {
        case .finish:
            finish(with: .success(outputURL))
        case .noSpeech:
            finish(with: .success(nil), deleteAudio: true)
        }
    }

    private func finish(with result: Result<URL?, Error>, deleteAudio: Bool = false) {
        guard let completion else { return }
        self.completion = nil
        meterTimer?.invalidate()
        meterTimer = nil

        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        startedAt = nil

        if deleteAudio, let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        self.outputURL = nil
        completion(result)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        finish(with: .failure(error ?? QuestionRecorderError.encodingFailed), deleteAudio: true)
    }
}
