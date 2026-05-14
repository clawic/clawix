import Foundation
import AVFoundation

/// Three cloud Whisper-as-a-service providers (#22 cloud variants):
/// Groq, Deepgram, and a generic Custom OpenAI-compatible
/// `/v1/audio/transcriptions` endpoint. Each takes a 16 kHz mono
/// WAV blob and returns the transcript as a string. API keys live in
/// the user's encrypted vault under the "Clawix System" container
/// (see `CloudTranscriptionSecrets`); Secrets must be unlocked.
///
/// These providers are dispatched from `DictationCoordinator.stop()`
/// when the user picks one in Settings → Voice to Text → Avanzado →
/// Transcription backend. The coordinator hands them the raw PCM
/// samples; they encode to WAV, upload, and return the result.
enum CloudTranscriptionProvider: String, CaseIterable {
    case groq
    case deepgram
    case custom

    var displayName: String {
        switch self {
        case .groq:     return "Groq (cloud)"
        case .deepgram: return "Deepgram (cloud)"
        case .custom:   return "Custom Whisper endpoint"
        }
    }

    static let baseURLKeyPrefix = "dictation.transcription.baseURL"
    static let modelKeyPrefix = "dictation.transcription.model"

    /// Transcribe a PCM Float32 buffer @ 16 kHz mono. Throws on
    /// network / decoding errors so the coordinator can fall back
    /// to local Whisper.
    func transcribe(samples: [Float], language: String?, prompt: String?) async throws -> String {
        switch self {
        case .groq:
            return try await transcribeGroq(samples: samples, language: language, prompt: prompt)
        case .deepgram:
            return try await transcribeDeepgram(samples: samples, language: language)
        case .custom:
            return try await transcribeCustom(samples: samples, language: language, prompt: prompt)
        }
    }

    // MARK: - Groq

    private func transcribeGroq(samples: [Float], language: String?, prompt: String?) async throws -> String {
        guard await CloudTranscriptionSecrets.hasAPIKey(for: .groq) else {
            throw CloudError.notConfigured
        }
        let model = UserDefaults.standard.string(forKey: "\(Self.modelKeyPrefix).\(rawValue)")
            ?? "whisper-large-v3"
        let url = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        let multipart = makeMultipartBody(
            audio: makeWAV(samples: samples),
            model: model,
            language: language,
            prompt: prompt
        )
        let response = try await SystemSecrets.brokerHttp(
            internalName: CloudTranscriptionSecrets.internalName(for: .groq),
            method: "POST",
            url: url,
            headers: [
                "Content-Type": multipart.contentType,
                "Authorization": "Bearer {{\(CloudTranscriptionSecrets.internalName(for: .groq)).value}}"
            ],
            body: nil,
            bodyData: multipart.body,
            agent: "clawix-transcription",
            riskTier: "cost",
            approvalSatisfied: true,
            timeoutMs: 60_000
        )
        return try parseOpenAIShape(data: brokerData(response), status: response.status, errorBody: response.bodyText)
    }

    // MARK: - Deepgram

    private func transcribeDeepgram(samples: [Float], language: String?) async throws -> String {
        guard await CloudTranscriptionSecrets.hasAPIKey(for: .deepgram) else {
            throw CloudError.notConfigured
        }
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        var queryItems = [URLQueryItem(name: "model", value: "nova-3")]
        if let language, language != "auto" {
            queryItems.append(URLQueryItem(name: "language", value: language))
        }
        queryItems.append(URLQueryItem(name: "smart_format", value: "true"))
        queryItems.append(URLQueryItem(name: "punctuate", value: "true"))
        components.queryItems = queryItems
        let response = try await SystemSecrets.brokerHttp(
            internalName: CloudTranscriptionSecrets.internalName(for: .deepgram),
            method: "POST",
            url: components.url!,
            headers: [
                "Authorization": "Token {{\(CloudTranscriptionSecrets.internalName(for: .deepgram)).value}}",
                "Content-Type": "audio/wav"
            ],
            body: nil,
            bodyData: makeWAV(samples: samples),
            agent: "clawix-transcription",
            riskTier: "cost",
            approvalSatisfied: true,
            timeoutMs: 60_000
        )
        if !response.ok {
            throw CloudError.http(response.status ?? 0, response.bodyText ?? "")
        }
        let data = brokerData(response)
        struct DeepgramResponse: Decodable {
            struct Result: Decodable {
                struct Channel: Decodable {
                    struct Alt: Decodable { let transcript: String }
                    let alternatives: [Alt]
                }
                let channels: [Channel]
            }
            let results: Result
        }
        do {
            let decoded = try JSONDecoder().decode(DeepgramResponse.self, from: data)
            return decoded.results.channels.first?.alternatives.first?.transcript ?? ""
        } catch {
            throw CloudError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Custom (OpenAI-compatible)

    private func transcribeCustom(samples: [Float], language: String?, prompt: String?) async throws -> String {
        guard let raw = UserDefaults.standard.string(forKey: "\(Self.baseURLKeyPrefix).\(rawValue)"),
              let baseURL = URL(string: raw) else {
            throw CloudError.notConfigured
        }
        let model = UserDefaults.standard.string(forKey: "\(Self.modelKeyPrefix).\(rawValue)")
            ?? "whisper-1"
        let endpoint = baseURL.appendingPathComponent("/audio/transcriptions")
        let multipart = makeMultipartBody(
            audio: makeWAV(samples: samples),
            model: model,
            language: language,
            prompt: prompt
        )
        if await CloudTranscriptionSecrets.hasAPIKey(for: .custom) {
            let response = try await SystemSecrets.brokerHttp(
                internalName: CloudTranscriptionSecrets.internalName(for: .custom),
                method: "POST",
                url: endpoint,
                headers: [
                    "Content-Type": multipart.contentType,
                    "Authorization": "Bearer {{\(CloudTranscriptionSecrets.internalName(for: .custom)).value}}"
                ],
                body: nil,
                bodyData: multipart.body,
                agent: "clawix-transcription",
                riskTier: "cost",
                approvalSatisfied: true,
                timeoutMs: 60_000
            )
            return try parseOpenAIShape(data: brokerData(response), status: response.status, errorBody: response.bodyText)
        }
        let (data, response) = try await uploadMultipart(url: endpoint, multipart: multipart)
        return try parseOpenAIShape(data: data, response: response)
    }

    // MARK: - Shared

    private func makeMultipartBody(
        audio: Data,
        model: String,
        language: String?,
        prompt: String?
    ) -> (body: Data, contentType: String) {
        let boundary = "clawix-\(UUID().uuidString)"
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("model", model)
        appendField("response_format", "json")
        if let language, language != "auto" {
            appendField("language", language)
        }
        if let prompt, !prompt.isEmpty {
            appendField("prompt", prompt)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return (body, "multipart/form-data; boundary=\(boundary)")
    }

    private func uploadMultipart(
        url: URL,
        multipart: (body: Data, contentType: String)
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = multipart.body
        return try await URLSession.shared.data(for: request)
    }

    private func brokerData(_ response: ClawJSSecretsClient.BrokerHTTPResponse) throws -> Data {
        if let bodyText = response.bodyText {
            return Data(bodyText.utf8)
        }
        if let bodyBase64 = response.bodyBase64, let data = Data(base64Encoded: bodyBase64) {
            return data
        }
        throw CloudError.decoding("Empty broker response.")
    }

    private func parseOpenAIShape(data: Data, status: Int?, errorBody: String?) throws -> String {
        if let status, !(200...299).contains(status) {
            throw CloudError.http(status, errorBody ?? String(data: data, encoding: .utf8) ?? "")
        }
        return try parseOpenAIShape(data: data)
    }

    private func parseOpenAIShape(data: Data, response: URLResponse) throws -> String {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw CloudError.http(http.statusCode, bodyText)
        }
        return try parseOpenAIShape(data: data)
    }

    private func parseOpenAIShape(data: Data) throws -> String {
        struct WhisperJSON: Decodable { let text: String }
        do {
            let decoded = try JSONDecoder().decode(WhisperJSON.self, from: data)
            return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw CloudError.decoding(error.localizedDescription)
        }
    }

    // MARK: - WAV encoder

    /// Encode `samples` (16 kHz mono Float32) as a 16-bit PCM WAV
    /// Data blob suitable for upload.
    private func makeWAV(samples: [Float]) -> Data {
        let sampleRate: Int = 16_000
        let bitsPerSample: Int = 16
        let channels: Int = 1
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataBytes = samples.count * (bitsPerSample / 8)
        var data = Data(capacity: 44 + dataBytes)
        data.append("RIFF".data(using: .ascii)!)
        data.append(uint32LE(UInt32(36 + dataBytes)))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(uint32LE(16))
        data.append(uint16LE(1)) // PCM
        data.append(uint16LE(UInt16(channels)))
        data.append(uint32LE(UInt32(sampleRate)))
        data.append(uint32LE(UInt32(byteRate)))
        data.append(uint16LE(UInt16(blockAlign)))
        data.append(uint16LE(UInt16(bitsPerSample)))
        data.append("data".data(using: .ascii)!)
        data.append(uint32LE(UInt32(dataBytes)))
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let value = Int16(clamped * Float(Int16.max))
            data.append(uint16LE(UInt16(bitPattern: value)))
        }
        return data
    }

    private func uint16LE(_ v: UInt16) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: MemoryLayout<UInt16>.size)
    }

    private func uint32LE(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: MemoryLayout<UInt32>.size)
    }
}

enum CloudError: Error, LocalizedError {
    case notConfigured
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Configure your provider's API key first."
        case .http(let code, let body):
            return "HTTP \(code): \(body.prefix(160))"
        case .decoding(let detail):
            return "Couldn't parse the response: \(detail)"
        }
    }
}
