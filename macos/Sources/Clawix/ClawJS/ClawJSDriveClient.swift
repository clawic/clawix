import Foundation

/// HTTP client for the bundled `@clawjs/drive` service. Mirrors the wire
/// shape of `clawjs/drive/src/server/app.ts` and the types declared in
/// `clawjs/drive/src/shared/types.ts`. Replicates the pattern of
/// `ClawJSVaultClient`: synchronous URLSession wrapper with admin JWT
/// renewal, multipart uploads, share polymorphism, and audit query.
final class ClawJSDriveClient {

    enum Error: Swift.Error, LocalizedError {
        case serviceNotReady
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case transport(Swift.Error)
        case duplicateExists(existing: DriveItem)

        var errorDescription: String? {
            switch self {
            case .serviceNotReady: return "ClawJS drive service is not running."
            case .invalidURL: return "Could not build a URL for the drive service."
            case .http(let status, let body): return "Drive returned HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .decoding(let error): return "Could not decode drive response: \(error.localizedDescription)"
            case .transport(let error): return "Could not reach drive service: \(error.localizedDescription)"
            case .duplicateExists: return "A file with the same content already exists in the Drive."
            }
        }
    }

    private let session: URLSession
    private let origin: URL
    var bearerToken: String?

    init(
        bearerToken: String? = nil,
        origin: URL = URL(string: "http://127.0.0.1:7792")!,
        session: URLSession = .shared
    ) {
        self.bearerToken = bearerToken
        self.origin = origin
        self.session = session
    }

    // MARK: - Wire types

    struct HealthResponse: Decodable {
        let ok: Bool
        let service: String
        let host: String
        let port: Int
    }

    struct AdminLoginResponse: Decodable {
        let accessToken: String
        let email: String
    }

    struct ViewCounts: Decodable, Equatable {
        let myDrive: Int
        let recent: Int
        let starred: Int
        let shared: Int
        let trash: Int
    }

    struct BootstrapResponse: Decodable {
        let counts: ViewCounts
    }

    struct DriveItem: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let kind: String
        let parentId: String?
        let mimeType: String?
        let sizeBytes: Int
        let starred: Bool
        let trashedAt: String?
        let previewKind: String
        let previewText: String
        let currentRevisionId: String?
        let childCount: Int
        let commentCount: Int
        let revisionCount: Int
        let shareCount: Int
        let createdAt: String
        let updatedAt: String
        let lastViewedAt: String?
    }

    struct DriveItemDetail: Decodable {
        let id: String
        let name: String
        let kind: String
        let parentId: String?
        let mimeType: String?
        let sizeBytes: Int
        let starred: Bool
        let trashedAt: String?
        let previewKind: String
        let previewText: String
        let currentRevisionId: String?
        let childCount: Int
        let commentCount: Int
        let revisionCount: Int
        let shareCount: Int
        let createdAt: String
        let updatedAt: String
        let lastViewedAt: String?
        let breadcrumbs: [Breadcrumb]
        struct Breadcrumb: Decodable, Hashable { let id: String; let name: String }
    }

    struct ListItemsResponse: Decodable {
        let items: [DriveItem]
        let counts: ViewCounts
        let breadcrumbs: [DriveItemDetail.Breadcrumb]
    }

    struct ExifRecord: Decodable {
        let itemId: String
        let takenAt: String?
        let cameraMake: String?
        let cameraModel: String?
        let lensModel: String?
        let iso: Int?
        let shutterSpeed: String?
        let aperture: Double?
        let focalLength: Double?
        let latitude: Double?
        let longitude: Double?
        let orientation: Int?
        let width: Int?
        let height: Int?
    }

    struct AgentShareRecord: Decodable, Hashable {
        let id: String
        let itemId: String
        let agentName: String
        let createdAt: String
        let expiresAt: String
        let revokedAt: String?
        let usedCount: Int
        let lastUsedAt: String?
    }

    struct TailnetShareRecord: Decodable, Hashable {
        let id: String
        let itemId: String
        let magicdnsName: String
        let createdAt: String
        let revokedAt: String?
    }

    struct TunnelShareRecord: Decodable, Hashable {
        let id: String
        let itemId: String
        let tunnelUrl: String
        let startedAt: String
        let stoppedAt: String?
        let status: String
    }

    struct ReadShareRecord: Decodable, Hashable {
        let id: String
        let itemId: String
        let label: String
        let mode: String
        let createdAt: String
        let revokedAt: String?
    }

    struct AllSharesResponse: Decodable {
        let read: [ReadShareRecord]
        let tailnet: [TailnetShareRecord]
        let tunnel: [TunnelShareRecord]
        let agent: [AgentShareRecord]
    }

    struct CreateAgentShareResponse: Decodable {
        let mode: String
        let record: AgentShareRecord
        let token: String
    }

    struct CreateReadShareResponse: Decodable {
        struct InnerShare: Decodable { let id: String; let itemId: String; let label: String; let mode: String }
        let share: InnerShare
        let token: String
        let url: String
    }

    struct AuditEvent: Decodable, Identifiable {
        let id: String
        let kind: String
        let itemId: String?
        let principalKind: String
        let principalId: String
        let principalName: String
        let timestamp: String
    }

    struct AuditQueryResponse: Decodable { let items: [AuditEvent] }

    struct SemanticResult: Decodable, Hashable {
        let itemId: String
        let score: Double
        let item: DriveItem
    }

    struct SemanticSearchResponse: Decodable { let items: [SemanticResult] }

    // MARK: - Health & auth

    func health() async throws -> HealthResponse {
        try await get("/v1/health")
    }

    func login(email: String, password: String) async throws -> AdminLoginResponse {
        let response: AdminLoginResponse = try await post("/v1/auth/admin/login", body: ["email": email, "password": password])
        self.bearerToken = response.accessToken
        return response
    }

    // MARK: - Items

    func bootstrap() async throws -> BootstrapResponse {
        try await get("/v1/bootstrap")
    }

    func listItems(view: String = "my-drive", parentId: String? = nil, query: String? = nil) async throws -> ListItemsResponse {
        var components = URLComponents(string: "/v1/items")!
        var items: [URLQueryItem] = [URLQueryItem(name: "view", value: view)]
        if let parentId = parentId { items.append(URLQueryItem(name: "parentId", value: parentId)) }
        if let query = query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        components.queryItems = items
        return try await get(components.url!.absoluteString)
    }

    func getItem(_ id: String) async throws -> DriveItemDetail {
        try await get("/v1/items/\(id)")
    }

    func createFolder(name: String, parentId: String?) async throws -> DriveItemDetail {
        try await post("/v1/items", body: ["kind": "folder", "name": name, "parentId": parentId as Any])
    }

    func updateItem(_ id: String, name: String? = nil, starred: Bool? = nil, parentId: String? = nil) async throws -> DriveItemDetail {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let starred { body["starred"] = starred }
        if let parentId { body["parentId"] = parentId }
        return try await patch("/v1/items/\(id)", body: body)
    }

    func moveItem(_ id: String, parentId: String?) async throws -> DriveItemDetail {
        try await post("/v1/items/\(id)/move", body: ["parentId": parentId as Any])
    }

    func copyItem(_ id: String, parentId: String?) async throws -> DriveItemDetail {
        try await post("/v1/items/\(id)/copy", body: ["parentId": parentId as Any])
    }

    func trashItem(_ id: String) async throws -> DriveItemDetail {
        try await post("/v1/items/\(id)/trash", body: nil)
    }

    func restoreItem(_ id: String) async throws -> DriveItemDetail {
        try await post("/v1/items/\(id)/restore", body: nil)
    }

    @discardableResult
    func deleteItem(_ id: String) async throws -> Bool {
        struct R: Decodable { let ok: Bool }
        let r: R = try await delete("/v1/items/\(id)")
        return r.ok
    }

    // MARK: - Uploads

    /// Upload a local file as a new item. `duplicatePolicy = "report"` makes
    /// the server respond with HTTP 409 if the SHA256 already exists.
    func upload(filePath: URL, parentId: String?, duplicatePolicy: String? = nil) async throws -> DriveItemDetail {
        let boundary = "Boundary-\(UUID().uuidString)"
        var pathString = "/v1/uploads"
        if let policy = duplicatePolicy {
            pathString += "?duplicatePolicy=\(policy)"
        }
        guard let url = URL(string: pathString, relativeTo: origin) else { throw Error.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var body = Data()
        let fileData = try Data(contentsOf: filePath)
        let fileName = filePath.lastPathComponent
        let mimeType = mimeTypeForExtension(filePath.pathExtension)

        if let parentId = parentId {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"parentId\"\r\n\r\n")
            body.appendString("\(parentId)\r\n")
        }
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.appendString("\r\n--\(boundary)--\r\n")

        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.transport(URLError(.badServerResponse))
        }
        if httpResponse.statusCode == 409 {
            // Duplicate path: parse and surface the existing item.
            struct DupResponse: Decodable { let error: String; let existing: DriveItem }
            if let dup = try? JSONDecoder().decode(DupResponse.self, from: data) {
                throw Error.duplicateExists(existing: dup.existing)
            }
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw Error.http(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }
        return try JSONDecoder().decode(DriveItemDetail.self, from: data)
    }

    func uploadData(_ data: Data, fileName: String, mimeType: String, parentId: String?) async throws -> DriveItemDetail {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + fileName)
        try data.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        return try await upload(filePath: tmpURL, parentId: parentId)
    }

    // MARK: - Downloads & thumbnails

    func downloadItem(_ id: String, to destination: URL) async throws {
        guard let url = URL(string: "/v1/items/\(id)/download", relativeTo: origin) else { throw Error.invalidURL }
        var request = URLRequest(url: url)
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (tempURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw Error.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: nil)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    func thumbnailData(_ id: String, size: Int = 256) async throws -> Data {
        guard let url = URL(string: "/v1/items/\(id)/thumbnail?size=\(size)", relativeTo: origin) else { throw Error.invalidURL }
        var request = URLRequest(url: url)
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw Error.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: nil)
        }
        return data
    }

    func getExif(_ id: String) async throws -> ExifRecord? {
        do { return try await get("/v1/items/\(id)/exif") }
        catch Error.http(404, _) { return nil }
    }

    // MARK: - Search

    func searchText(_ query: String) async throws -> [DriveItem] {
        struct Response: Decodable { let items: [DriveItem] }
        let response: Response = try await get("/v1/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        return response.items
    }

    func searchSemantic(_ query: String, limit: Int = 20) async throws -> [SemanticResult] {
        let response: SemanticSearchResponse = try await post("/v1/search/semantic", body: ["query": query, "limit": limit])
        return response.items
    }

    // MARK: - Sharing

    func listAllShares(_ itemId: String) async throws -> AllSharesResponse {
        try await get("/v1/items/\(itemId)/shares/all")
    }

    func createReadShare(_ itemId: String, label: String) async throws -> CreateReadShareResponse {
        try await post("/v1/items/\(itemId)/shares", body: ["mode": "read", "label": label])
    }

    func createTailnetShare(_ itemId: String) async throws -> TailnetShareRecord {
        struct Response: Decodable { let mode: String; let record: TailnetShareRecord }
        let r: Response = try await post("/v1/items/\(itemId)/shares", body: ["mode": "tailnet"])
        return r.record
    }

    func createTunnelShare(_ itemId: String) async throws -> TunnelShareRecord {
        struct Response: Decodable { let mode: String; let record: TunnelShareRecord }
        let r: Response = try await post("/v1/items/\(itemId)/shares", body: ["mode": "public_tunnel"])
        return r.record
    }

    func createAgentShare(_ itemId: String, capabilityKind: String, ttlMinutes: Int, reason: String?, agentName: String) async throws -> CreateAgentShareResponse {
        var body: [String: Any] = [
            "mode": "agent",
            "capabilityKind": capabilityKind,
            "ttlMinutes": ttlMinutes,
            "agentName": agentName,
        ]
        if let reason = reason { body["reason"] = reason }
        return try await post("/v1/items/\(itemId)/shares", body: body)
    }

    @discardableResult
    func revokeShare(_ itemId: String, _ shareId: String) async throws -> Bool {
        struct R: Decodable { let ok: Bool }
        let r: R = try await post("/v1/items/\(itemId)/shares/\(shareId)/revoke", body: nil)
        return r.ok
    }

    // MARK: - Audit & encrypted folders

    func queryAudit(kinds: [String]? = nil, itemId: String? = nil, limit: Int = 200) async throws -> [AuditEvent] {
        var components = URLComponents(string: "/v1/audit")!
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let kinds = kinds, !kinds.isEmpty { items.append(URLQueryItem(name: "kinds", value: kinds.joined(separator: ","))) }
        if let itemId { items.append(URLQueryItem(name: "itemId", value: itemId)) }
        components.queryItems = items
        let response: AuditQueryResponse = try await get(components.url!.absoluteString)
        return response.items
    }

    func setEncryptedFolder(_ folderId: String, enabled: Bool) async throws {
        struct R: Decodable { let ok: Bool }
        let _: R = try await post("/v1/encrypted-folders", body: ["folderId": folderId, "enabled": enabled])
    }

    // MARK: - Project folder ensure (Clawix auto-routing entry point)

    func ensureProjectFolder(slug: String) async throws -> String {
        struct R: Decodable { let folderId: String }
        let r: R = try await post("/v1/projects/\(slug)/ensure-folder", body: nil)
        return r.folderId
    }

    // MARK: - Internal HTTP helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path: path, method: "GET", body: nil)
    }

    private func post<T: Decodable>(_ path: String, body: Any?) async throws -> T {
        try await request(path: path, method: "POST", body: body)
    }

    private func patch<T: Decodable>(_ path: String, body: Any?) async throws -> T {
        try await request(path: path, method: "PATCH", body: body)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        try await request(path: path, method: "DELETE", body: nil)
    }

    private func request<T: Decodable>(path: String, method: String, body: Any?) async throws -> T {
        guard let url = URL(string: path, relativeTo: origin) else { throw Error.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let cleaned = sanitize(body)
            request.httpBody = try JSONSerialization.data(withJSONObject: cleaned, options: [])
        }
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { throw Error.transport(error) }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.transport(URLError(.badServerResponse))
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw Error.http(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw Error.decoding(error) }
    }

    /// Strip `NSNull`-equivalents from optional values cast to `Any`.
    private func sanitize(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, child) in dict {
                let cleaned = sanitize(child)
                if cleaned is NSNull { continue }
                out[key] = cleaned
            }
            return out
        }
        if value is NSNull { return NSNull() }
        if let optional = value as? Optional<Any>, optional == nil { return NSNull() }
        return value
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "md": return "text/markdown"
        case "json": return "application/json"
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        default: return "application/octet-stream"
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
