import Foundation

enum TranscriptionRoute: Equatable {
    case openAI
    case macOS

    static func preferred(openAIKey: String?) -> Self {
        guard let openAIKey,
              !openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .macOS
        }
        return .openAI
    }
}

enum OpenAITranscriptionError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case emptyTranscription

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Chave da OpenAI não configurada. Abra Configurações no menu do Pynkaro."
        case .invalidResponse:
            return "A OpenAI retornou uma resposta de transcrição inválida."
        case .httpError(let statusCode, let message):
            return "Erro da OpenAI (HTTP \(statusCode)): \(message)"
        case .emptyTranscription:
            return "A OpenAI não encontrou fala no áudio enviado."
        }
    }
}

enum OpenAITranscriptionRequestBuilder {
    static func makeRequest(apiKey: String,
                            audioData: Data,
                            filename: String = "question.m4a",
                            boundary: String = "Boundary-\(UUID().uuidString)") -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        appendField(name: "model", value: "gpt-4o-transcribe", boundary: boundary, to: &body)
        appendField(name: "language", value: "pt", boundary: boundary, to: &body)
        appendField(name: "response_format", value: "json", boundary: boundary, to: &body)
        appendFile(name: "file",
                   filename: filename,
                   mimeType: "audio/mp4",
                   data: audioData,
                   boundary: boundary,
                   to: &body)
        body.appendUTF8("--\(boundary)--\r\n")
        request.httpBody = body
        return request
    }

    private static func appendField(name: String,
                                    value: String,
                                    boundary: String,
                                    to body: inout Data) {
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.appendUTF8("\(value)\r\n")
    }

    private static func appendFile(name: String,
                                   filename: String,
                                   mimeType: String,
                                   data: Data,
                                   boundary: String,
                                   to body: inout Data) {
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        )
        body.appendUTF8("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.appendUTF8("\r\n")
    }
}

final class OpenAITranscriptionClient {
    @discardableResult
    func transcribe(audioURL: URL,
                    completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        guard let apiKey = Config.openAIKey else {
            completion(.failure(OpenAITranscriptionError.missingAPIKey))
            return nil
        }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            completion(.failure(error))
            return nil
        }

        let request = OpenAITranscriptionRequestBuilder.makeRequest(
            apiKey: apiKey,
            audioData: audioData,
            filename: audioURL.lastPathComponent
        )
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse, let data else {
                completion(.failure(OpenAITranscriptionError.invalidResponse))
                return
            }
            do {
                completion(.success(try Self.parseResponse(data: data, statusCode: response.statusCode)))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
        return task
    }

    static func parseResponse(data: Data, statusCode: Int) throws -> String {
        guard (200...299).contains(statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = json?["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "Falha ao transcrever o áudio."
            throw OpenAITranscriptionError.httpError(statusCode: statusCode, message: message)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAITranscriptionError.invalidResponse
        }

        guard let text = json["text"] as? String else {
            throw OpenAITranscriptionError.invalidResponse
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAITranscriptionError.emptyTranscription
        }
        return trimmed
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
