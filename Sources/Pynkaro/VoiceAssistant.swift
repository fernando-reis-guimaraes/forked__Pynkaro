import Foundation
import AVFoundation
import Speech

/// Máquina de estados do assistente:
/// wake word local → gravação → transcrição OpenAI → Claude → fala → volta ao início.
final class VoiceAssistant: NSObject {

    private enum State {
        case waitingWakeWord
        case capturingQuestion
        case transcribing
        case thinking
        case speaking
    }

    /// Wake words separadas por vírgula em PYNKARO_WAKE_WORDS.
    /// A comparação ignora maiúsculas, minúsculas e acentos.
    /// PYNKARO_WAKE_WORD é mantida como fallback de compatibilidade.
    private let wakeWords: [String] = {
        let environment = ProcessInfo.processInfo.environment

        if let csv = environment["PYNKARO_WAKE_WORDS"] {
            let values = csv
                .split(separator: ",", omittingEmptySubsequences: false)
                .map {
                    String($0)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                }
                .filter { !$0.isEmpty }

            if !values.isEmpty {
                return values
            }
        }

        if let legacy = environment["PYNKARO_WAKE_WORD"] {
            let value = legacy
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            if !value.isEmpty {
                return [value]
            }
        }

        return ["pincaro"]
    }()

    /// Quando PYNKARO_VERBOSE=1, imprime as parciais usadas para detectar a wake word.
    private let isVerbose =
        ProcessInfo.processInfo.environment["PYNKARO_VERBOSE"] == "1"

    /// Notifica a interface (menu bar) sobre mudanças de estado.
    var onStatusChange: ((AssistantStatus) -> Void)?

    /// Frases que cancelam a pergunta depois da transcrição, sem consultar o Claude.
    private let cancelPhrases = ["esquece", "esqueca", "deixa pra la", "deixa para la", "cancela"]

    private var state: State = .waitingWakeWord {
        didSet { emitStatus() }
    }
    private var isPaused = false {
        didSet { emitStatus() }
    }

    private let recognizer = SpeechRecognizer()
    private let questionRecorder = QuestionRecorder()
    private let transcriber = OpenAITranscriptionClient()
    private let speaker: Speaking = {
        if let key = Config.elevenLabsKey {
            return ElevenLabsSpeaker(apiKey: key)
        }
        return Speaker()
    }()
    private let claude = ClaudeClient()
    private lazy var avatar = AvatarWindow()

    private var lastVerboseTranscript = ""
    private var operationGeneration = 0
    private var transcriptionTask: URLSessionDataTask?
    private var pendingAudioURL: URL?

    private func emitStatus() {
        let status: AssistantStatus
        if isPaused {
            status = .paused
        } else {
            switch state {
            case .waitingWakeWord:   status = .waiting
            case .capturingQuestion: status = .listening
            case .transcribing:      status = .transcribing
            case .thinking:          status = .thinking
            case .speaking:          status = .speaking
            }
        }
        onStatusChange?(status)
    }

    // MARK: - Pausa (menu bar)

    /// Interrompe captura e transcrição sem encerrar o app.
    func pause() {
        guard !isPaused else { return }
        operationGeneration += 1
        isPaused = true
        recognizer.stopListening()
        questionRecorder.cancel()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        removePendingAudio()
        avatar.hide()
        state = .waitingWakeWord
        print("⏸️ Escuta pausada.")
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        print("👂 Escuta retomada. Aguardando \"\(wakeWords[0])\"...")
        restartListening()
    }

    // MARK: - Inicialização e permissões

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            guard auth == .authorized else {
                print("❌ Permissão de reconhecimento de fala negada.")
                print("   Habilite em Ajustes do Sistema > Privacidade e Segurança > Reconhecimento de Fala.")
                exit(1)
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                guard granted else {
                    print("❌ Permissão de microfone negada.")
                    print("   Habilite em Ajustes do Sistema > Privacidade e Segurança > Microfone.")
                    exit(1)
                }
                DispatchQueue.main.async { self?.setup() }
            }
        }
    }

    private func setup() {
        if recognizer.isOnDevice {
            print("🔒 Detecção da wake word 100% local (on-device).")
        } else {
            print("⚠️ Este Mac não suporta reconhecimento on-device em pt-BR;")
            print("   a wake word será processada nos servidores da Apple.")
            print("   (Baixe o idioma em Ajustes > Teclado > Ditado para ativar o modo local.)")
        }

        recognizer.contextualStrings = wakeWords

        speaker.onMouthLevel = { [weak self] level in
            self?.avatar.setMouth(level)
        }

        recognizer.onPartial = { [weak self] text in
            DispatchQueue.main.async { self?.handleWakeWordPartial(text) }
        }
        recognizer.onError = { [weak self] _ in
            DispatchQueue.main.async { self?.recoverListening() }
        }

        // O SFSpeechRecognizer limita sessões a ~1 minuto.
        Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            guard let self, self.state == .waitingWakeWord, !self.isPaused else { return }
            self.restartListening()
        }

        emitStatus()
        restartListening()
        print("👂 Aguardando \"\(wakeWords[0])\"... (Ctrl+C para sair)")
    }

    // MARK: - Wake word local

    private func restartListening() {
        guard !isPaused, state == .waitingWakeWord else { return }
        lastVerboseTranscript = ""
        do {
            try recognizer.startListening()
        } catch {
            print("⚠️ Falha ao iniciar o áudio: \(error.localizedDescription). Tentando de novo em 2s...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.restartListening()
            }
        }
    }

    private func recoverListening() {
        guard !isPaused, state == .waitingWakeWord else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.restartListening()
        }
    }

    private func handleWakeWordPartial(_ text: String) {
        guard !isPaused, state == .waitingWakeWord else { return }

        if isVerbose && text != lastVerboseTranscript {
            lastVerboseTranscript = text
            print("🔎 Wake word: \(text)")
        }

        guard wakeWords.contains(where: {
            text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }) else { return }

        // O reconhecedor local para aqui. A pergunta será apenas gravada e enviada à OpenAI.
        recognizer.stopListening()
        beginQuestionCapture()
    }

    // MARK: - Gravação e transcrição

    private func beginQuestionCapture() {
        operationGeneration += 1
        let generation = operationGeneration
        state = .capturingQuestion
        avatar.show()
        avatar.setCaption("Pode falar…")

        do {
            try questionRecorder.start { [weak self] result in
                DispatchQueue.main.async {
                    self?.handleRecordingResult(result, generation: generation)
                }
            }
            print("🎤 Pode falar...")
        } catch {
            handleRecordingResult(.failure(error), generation: generation)
        }
    }

    private func handleRecordingResult(_ result: Result<URL?, Error>, generation: Int) {
        guard generation == operationGeneration,
              !isPaused,
              state == .capturingQuestion else { return }

        switch result {
        case .failure(let error):
            handleOperationalError(
                error,
                message: "Desculpe, não consegui gravar sua pergunta.",
                generation: generation
            )

        case .success(nil):
            print("😴 Nenhuma fala detectada. Voltando a aguardar.")
            returnToWakeWord()

        case .success(let audioURL?):
            pendingAudioURL = audioURL
            state = .transcribing
            avatar.setCaption("Transcrevendo…")
            print("☁️ Transcrevendo pergunta com a OpenAI...")

            transcriptionTask = transcriber.transcribe(audioURL: audioURL) { [weak self] result in
                DispatchQueue.main.async {
                    self?.handleTranscriptionResult(
                        result,
                        audioURL: audioURL,
                        generation: generation
                    )
                }
            }
        }
    }

    private func handleTranscriptionResult(_ result: Result<String, Error>,
                                           audioURL: URL,
                                           generation: Int) {
        try? FileManager.default.removeItem(at: audioURL)
        if pendingAudioURL == audioURL {
            pendingAudioURL = nil
        }

        guard generation == operationGeneration,
              !isPaused,
              state == .transcribing else { return }
        transcriptionTask = nil

        switch result {
        case .failure(let error):
            handleOperationalError(
                error,
                message: "Desculpe, não consegui transcrever sua pergunta.",
                generation: generation
            )

        case .success(let question):
            print("📝 Transcrição: \(question)")
            avatar.setCaption("Você: \(question)")

            if isCancelRequest(question) {
                print("🙈 Cancelado por voz. Voltando a aguardar.")
                returnToWakeWord()
                return
            }

            state = .thinking
            print("🧠 Pergunta: \(question)")
            claude.ask(question) { [weak self] result in
                DispatchQueue.main.async {
                    self?.handleAnswer(result, generation: generation)
                }
            }
        }
    }

    private func isCancelRequest(_ text: String) -> Bool {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "pt_BR"))
            .lowercased()
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        return cancelPhrases.contains { normalized == $0 || normalized.hasSuffix(" " + $0) }
    }

    // MARK: - Claude e fala

    private func handleAnswer(_ result: Result<String, Error>, generation: Int) {
        guard generation == operationGeneration,
              !isPaused,
              state == .thinking else { return }

        let reply: String
        switch result {
        case .success(let text):
            reply = text
        case .failure(let error):
            print("⚠️ Erro na API: \(error.localizedDescription)")
            reply = "Desculpe, não consegui falar com a inteligência artificial agora."
        }

        speak(reply, generation: generation)
    }

    private func handleOperationalError(_ error: Error, message: String, generation: Int) {
        print("⚠️ \(error.localizedDescription)")
        speak(message, generation: generation)
    }

    private func speak(_ reply: String, generation: Int) {
        guard generation == operationGeneration, !isPaused else { return }
        print("💬 \(reply)")
        state = .speaking
        avatar.setCaption(reply)
        speaker.speak(reply) { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      generation == self.operationGeneration,
                      !self.isPaused,
                      self.state == .speaking else { return }
                self.returnToWakeWord()
            }
        }
    }

    private func returnToWakeWord() {
        questionRecorder.cancel()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        removePendingAudio()
        avatar.hide()
        state = .waitingWakeWord
        guard !isPaused else { return }
        print("👂 Aguardando \"\(wakeWords[0])\"...")
        restartListening()
    }

    private func removePendingAudio() {
        if let pendingAudioURL {
            try? FileManager.default.removeItem(at: pendingAudioURL)
        }
        pendingAudioURL = nil
    }
}
