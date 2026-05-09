import Foundation

/// Shared HTTP helpers for the provider clients. Centralizes the
/// `URLRequest` construction, timeout policy, error mapping, and JSON
/// decoding so each `*Client.swift` only owns provider-specific shape.
enum AIHTTP {

    static let shared: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    static func send(_ request: URLRequest, timeoutSeconds: Int) async throws -> (Data, HTTPURLResponse) {
        var req = request
        req.timeoutInterval = TimeInterval(timeoutSeconds)
        do {
            let (data, response) = try await shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw AIClientError.provider("non-HTTP response")
            }
            if (200..<300).contains(http.statusCode) {
                return (data, http)
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIClientError.http(http.statusCode, body)
        } catch let error as AIClientError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw AIClientError.timedOut
        } catch let error as URLError where error.code == .cancelled {
            throw AIClientError.cancelled
        } catch {
            throw AIClientError.provider(error.localizedDescription)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw AIClientError.decoding("\(error.localizedDescription) — \(preview)")
        }
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw AIClientError.provider("encoding failed: \(error.localizedDescription)")
        }
    }

    /// Multipart helper for STT endpoints. The boundary is fixed per call
    /// so callers can build it inline.
    static func multipart(boundary: String, parts: [Multipart]) -> Data {
        var data = Data()
        for part in parts {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            switch part {
            case .text(let name, let value):
                data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                data.append(value.data(using: .utf8) ?? Data())
                data.append("\r\n".data(using: .utf8)!)
            case .file(let name, let filename, let mime, let fileData):
                data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
                data.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
                data.append(fileData)
                data.append("\r\n".data(using: .utf8)!)
            }
        }
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }

    enum Multipart {
        case text(name: String, value: String)
        case file(name: String, filename: String, mime: String, data: Data)
    }
}
