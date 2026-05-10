import Foundation

/// Full HTTP client for the bundled `@clawjs/database` daemon.
/// Wraps the REST surface exposed by `packages/clawjs-database/src/app.ts`.
///
/// The client is a struct holding a bearer token; instances are cheap to
/// copy. `DatabaseManager` owns a single live instance and refreshes the
/// JWT before it expires.
struct DatabaseClient {

    enum Error: Swift.Error, LocalizedError {
        case serviceNotReady
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case transport(Swift.Error)
        case missingToken

        var errorDescription: String? {
            switch self {
            case .serviceNotReady:
                return "ClawJS database service is not running."
            case .invalidURL:
                return "Could not build a URL for the database service."
            case .http(let status, let body):
                return "Database returned HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .decoding(let error):
                return "Could not decode database response: \(error.localizedDescription)"
            case .transport(let error):
                return "Could not reach database service: \(error.localizedDescription)"
            case .missingToken:
                return "Database call requires authentication; no JWT yet."
            }
        }
    }

    var bearerToken: String?
    let origin: URL

    init(
        bearerToken: String? = nil,
        origin: URL = URL(string: "http://127.0.0.1:\(ClawJSService.database.port)")!
    ) {
        self.bearerToken = bearerToken
        self.origin = origin
    }

    // MARK: - Health

    struct HealthResponse: Codable, Equatable {
        let ok: Bool
        let service: String
        let host: String
        let port: Int
    }

    func probeHealth() async throws -> HealthResponse {
        try await get("/v1/health", authenticated: false)
    }

    // MARK: - Auth

    struct LoginResponse: Codable, Equatable {
        let accessToken: String
        let admin: Admin

        struct Admin: Codable, Equatable {
            let id: String
            let email: String
        }
    }

    struct BootstrapResponse: Codable, Equatable {
        let accessToken: String
        let admin: LoginResponse.Admin
        let created: Bool?
    }

    /// Idempotent. First call creates the admin; subsequent calls return
    /// a fresh JWT for the same credential. 401 if the email exists with
    /// a different password.
    func bootstrapAdmin(email: String, password: String) async throws -> BootstrapResponse {
        try await post("/v1/auth/admin/bootstrap", body: [
            "email": email,
            "password": password,
        ], authenticated: false)
    }

    func loginAdmin(email: String, password: String) async throws -> LoginResponse {
        try await post("/v1/auth/admin/login", body: [
            "email": email,
            "password": password,
        ], authenticated: false)
    }

    // MARK: - Namespaces

    private struct NamespacesEnvelope: Codable {
        let items: [DBNamespace]
    }

    func listNamespaces() async throws -> [DBNamespace] {
        let env: NamespacesEnvelope = try await get("/v1/namespaces")
        return env.items
    }

    /// Idempotent: PUT /v1/namespaces/:id creates if missing, otherwise
    /// returns existing. Backend seeds built-in collections on creation
    /// and on each call.
    func ensureNamespace(id: String, displayName: String? = nil) async throws -> DBNamespace {
        try await request(
            method: "PUT",
            path: "/v1/namespaces/\(id)",
            body: ["displayName": displayName ?? id]
        )
    }

    // MARK: - Collections

    private struct CollectionsEnvelope: Codable {
        let items: [DBCollection]
    }

    func listCollections(namespaceId: String) async throws -> [DBCollection] {
        let env: CollectionsEnvelope = try await get("/v1/namespaces/\(namespaceId)/collections")
        return env.items
    }

    func getCollection(namespaceId: String, name: String) async throws -> DBCollection {
        try await get("/v1/namespaces/\(namespaceId)/collections/\(name)")
    }

    func updateCollection(
        namespaceId: String,
        name: String,
        displayName: String,
        fields: [DBFieldDefinition],
        indexes: [DBIndexDefinition]
    ) async throws -> DBCollection {
        try await request(
            method: "PATCH",
            path: "/v1/namespaces/\(namespaceId)/collections/\(name)",
            body: [
                "displayName": displayName,
                "fields": fields.map(Self.fieldBody),
                "indexes": indexes.map(Self.indexBody),
            ]
        )
    }

    // MARK: - Records

    func listRecords(
        namespaceId: String,
        collection: String,
        filter: [String: Any]? = nil,
        sort: String? = nil,
        limit: Int? = 200,
        offset: Int? = 0
    ) async throws -> DBListResponse<DBRecord> {
        var components = URLComponents()
        components.path = "/v1/namespaces/\(namespaceId)/collections/\(collection)/records"
        var items: [URLQueryItem] = []
        if let filter, let data = try? JSONSerialization.data(withJSONObject: filter),
           let str = String(data: data, encoding: .utf8) {
            items.append(URLQueryItem(name: "filter", value: str))
        }
        if let sort { items.append(URLQueryItem(name: "sort", value: sort)) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let offset { items.append(URLQueryItem(name: "offset", value: String(offset))) }
        components.queryItems = items.isEmpty ? nil : items
        let path = components.url(relativeTo: origin)?.path ?? components.path
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await get("\(path)\(query)")
    }

    func getRecord(namespaceId: String, collection: String, id: String) async throws -> DBRecord {
        try await get("/v1/namespaces/\(namespaceId)/collections/\(collection)/records/\(id)")
    }

    func createRecord(
        namespaceId: String,
        collection: String,
        data: [String: DBJSON]
    ) async throws -> DBRecord {
        let body: [String: Any] = data.mapValues { $0.foundationValue }
        return try await post(
            "/v1/namespaces/\(namespaceId)/collections/\(collection)/records",
            body: body
        )
    }

    func updateRecord(
        namespaceId: String,
        collection: String,
        id: String,
        data: [String: DBJSON]
    ) async throws -> DBRecord {
        let body: [String: Any] = data.mapValues { $0.foundationValue }
        return try await request(
            method: "PATCH",
            path: "/v1/namespaces/\(namespaceId)/collections/\(collection)/records/\(id)",
            body: body
        )
    }

    @discardableResult
    func deleteRecord(namespaceId: String, collection: String, id: String) async throws -> Bool {
        let env: OkEnvelope = try await request(
            method: "DELETE",
            path: "/v1/namespaces/\(namespaceId)/collections/\(collection)/records/\(id)",
            body: nil
        )
        return env.ok
    }

    // MARK: - Files

    private struct FilesEnvelope: Codable { let items: [DBFileAsset] }
    private struct OkEnvelope: Codable { let ok: Bool }

    func listFiles(namespaceId: String) async throws -> [DBFileAsset] {
        let env: FilesEnvelope = try await get("/v1/namespaces/\(namespaceId)/files")
        return env.items
    }

    func uploadFile(
        namespaceId: String,
        collectionName: String?,
        recordId: String?,
        filename: String,
        contentType: String,
        data: Data
    ) async throws -> DBFileAsset {
        guard let token = bearerToken else { throw Error.missingToken }
        let url = URL(string: "/v1/files", relativeTo: origin)!.absoluteURL
        let boundary = "----DatabaseClientBoundary\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) {
            if let d = string.data(using: .utf8) { body.append(d) }
        }
        func appendField(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        appendField("namespaceId", namespaceId)
        if let collectionName { appendField("collectionName", collectionName) }
        if let recordId { appendField("recordId", recordId) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        let (responseData, response) = try await dataTask(request)
        try Self.validate(response: response, body: responseData)
        return try Self.decoder.decode(DBFileAsset.self, from: responseData)
    }

    func downloadFile(fileId: String) async throws -> Data {
        guard let token = bearerToken else { throw Error.missingToken }
        let url = URL(string: "/v1/files/\(fileId)", relativeTo: origin)!.absoluteURL
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await dataTask(request)
        try Self.validate(response: response, body: data)
        return data
    }

    @discardableResult
    func deleteFile(fileId: String) async throws -> Bool {
        let env: OkEnvelope = try await request(method: "DELETE", path: "/v1/files/\(fileId)", body: nil)
        return env.ok
    }

    // MARK: - Tokens (read-only from the app; CLI handles writes)

    private struct TokensEnvelope: Codable { let items: [DBScopedToken] }

    func listScopedTokens(namespaceId: String) async throws -> [DBScopedToken] {
        let env: TokensEnvelope = try await get("/v1/namespaces/\(namespaceId)/tokens")
        return env.items
    }

    // MARK: - Transport

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        return dec
    }()

    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        return enc
    }()

    private static func fieldBody(_ field: DBFieldDefinition) -> [String: Any] {
        var body: [String: Any] = [
            "name": field.name,
            "type": field.type.rawValue,
        ]
        if let required = field.required { body["required"] = required }
        if let options = field.options { body["options"] = options }
        if let relation = field.relation {
            body["relation"] = ["collectionName": relation.collectionName]
        }
        if let min = field.min { body["min"] = min }
        if let max = field.max { body["max"] = max }
        if let minLength = field.minLength { body["minLength"] = minLength }
        if let maxLength = field.maxLength { body["maxLength"] = maxLength }
        if let pattern = field.pattern { body["pattern"] = pattern }
        if let unique = field.unique { body["unique"] = unique }
        if let enumScale = field.enumScale { body["enumScale"] = enumScale }
        if let barcodeKind = field.barcodeKind { body["barcodeKind"] = barcodeKind }
        if let durationDisplayUnit = field.durationDisplayUnit { body["durationDisplayUnit"] = durationDisplayUnit }
        return body
    }

    private static func indexBody(_ index: DBIndexDefinition) -> [String: Any] {
        var body: [String: Any] = [
            "name": index.name,
            "fields": index.fields,
        ]
        if let unique = index.unique { body["unique"] = unique }
        return body
    }

    private func get<T: Decodable>(_ path: String, authenticated: Bool = true) async throws -> T {
        try await request(method: "GET", path: path, body: nil, authenticated: authenticated)
    }

    private func post<T: Decodable>(_ path: String, body: Any, authenticated: Bool = true) async throws -> T {
        try await request(method: "POST", path: path, body: body, authenticated: authenticated)
    }

    private func request<T: Decodable>(
        method: String,
        path: String,
        body: Any?,
        authenticated: Bool = true
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin)?.absoluteURL else {
            throw Error.invalidURL
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let token = bearerToken else { throw Error.missingToken }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw Error.decoding(error)
            }
        }
        let (data, response) = try await dataTask(req)
        try Self.validate(response: response, body: data)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw Error.decoding(error)
        }
    }

    private static func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if !(200..<300).contains(http.statusCode) {
            let string = String(data: body, encoding: .utf8)
            throw Error.http(status: http.statusCode, body: string)
        }
    }

    private func dataTask(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw Error.transport(error)
        }
    }
}
