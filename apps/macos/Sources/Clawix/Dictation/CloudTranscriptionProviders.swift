import Foundation
import AVFoundation

/// Three cloud Whisper-as-a-service providers (#22 cloud variants):
/// Groq, Deepgram, and a generic Custom OpenAI-compatible
/// `/v1/audio/transcriptions` endpoint. Each takes a 16 kHz mono
/// WAV blob and returns the transcript as a string. API keys live in
/// the same Keychain namespace as the Enhancement keys but with a
/// different `service` prefix so they don't collide.
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

    static let keychainServiceBase = "com.clawix.transcription"

    func service() -> String {
        "\(Self.keychainServiceBase).\(rawValue)"
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
        guard let key = readKey(for: .groq), !key.isEmpty else {
            throw CloudError.notConfigured
        }
        let model = UserDefaults.standard.string(forKey: "\(Self.modelKeyPrefix).\(rawValue)")
            ?? "whisper-large-v3"
        let url = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        let wav = makeWAV(samples: samples)
        let (data, response) = try await uploadMultipart(
            url: url,
            audio: wav,
            model: model,
            language: language,
            prompt: prompt,
            apiKey: key
        )
        return try parseOpenAIShape(data: data, response: response)
    }

    // MARK: - Deepgram

    private func transcribeDeepgram(samples: [Float], language: String?) async throws -> String {
        guard let key = readKey(for: .deepgram), !key.isEmpty else {
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
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeWAV(samples: samples)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw CloudError.http(http.statusCode, bodyText)
        }
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
        let key = readKey(for: .custom) // optional
        let endpoint = baseURL.appendingPathComponent("/audio/transcriptions")
        let wav = makeWAV(samples: samples)
        let (data, response) = try await uploadMultipart(
            url: endpoint,
            audio: wav,
            model: model,
            language: language,
            prompt: prompt,
            apiKey: key ?? ""
        )
        return try parseOpenAIShape(data: data, response: response)
    }

    // MARK: - Shared

    private func uploadMultipart(
        url: URL,
        audio: Data,
        model: String,
        language: String?,
        prompt: String?,
        apiKey: String
    ) async throws -> (Data, URLResponse) {
        let boundary = "clawix-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 60

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
        request.httpBody = body

        return try await URLSession.shared.data(for: request)
    }

    private func parseOpenAIShape(data: Data, response: URLResponse) throws -> String {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw CloudError.http(http.statusCode, bodyText)
        }
        struct WhisperJSON: Decodable { let text: String }
        do {
            let decoded = try JSONDecoder().decode(WhisperJSON.self, from: data)
            return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw CloudError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Keychain (separate namespace from Enhancement)

    func readKey(for provider: CloudTranscriptionProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.service(),
            kSecAttrAccount as String: "default",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func writeKey(_ key: String, for provider: CloudTranscriptionProvider) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.service(),
            kSecAttrAccount as String: "default"
        ]
        SecItemDelete(baseQuery as CFDictionary)
        guard !key.isEmpty, let data = key.data(using: .utf8) else { return }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func hasKey(for provider: CloudTranscriptionProvider) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: provider.service(),
            kSecAttrAccount as String: "default",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
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
