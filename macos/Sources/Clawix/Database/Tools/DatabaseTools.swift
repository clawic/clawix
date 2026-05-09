import Foundation

/// Typed tool surface that exposes the database to programmatic
/// callers: future MCP server, App Intents, Codex tool integration,
/// or in-app shortcut handlers.
///
/// Each tool corresponds to a JSON Schema definition + a Swift handler
/// that executes against `DatabaseManager`. The JSON Schema is what
/// gets advertised to the LLM (tomorrow, via an MCP server bundled
/// inside ClawJS or registered with Codex). For today, the in-process
/// handlers are the canonical execution path.
@MainActor
struct DatabaseTools {

    let manager: DatabaseManager

    init(manager: DatabaseManager) {
        self.manager = manager
    }

    // MARK: - Public surface

    func handle(toolName: String, arguments: [String: DBJSON]) async throws -> DBJSON {
        switch toolName {
        case "database_create_task":   return try await createTask(arguments)
        case "database_update_task":   return try await updateTask(arguments)
        case "database_complete_task": return try await completeTask(arguments)
        case "database_create_note":   return try await createNote(arguments)
        case "database_create_goal":   return try await createGoal(arguments)
        case "database_find_records":  return try await findRecords(arguments)
        default:
            throw NSError(domain: "DatabaseTools", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Unknown tool \(toolName)"
            ])
        }
    }

    /// JSON Schema definitions advertised to the LLM via MCP/tool-use.
    /// Returned as a JSON-serializable array so the caller (Codex tool
    /// registration, MCP server) can hand it off without further work.
    static let definitions: [[String: Any]] = [
        [
            "name": "database_create_task",
            "description": "Create a new task in the user's local productivity database. Returns the created record id.",
            "parameters": [
                "type": "object",
                "required": ["title"],
                "properties": [
                    "title":       ["type": "string"],
                    "description": ["type": "string"],
                    "status":      ["type": "string", "enum": ["todo", "in_progress", "blocked", "done", "cancelled"]],
                    "priority":    ["type": "string", "enum": ["low", "medium", "high", "urgent"]],
                    "dueAt":       ["type": "string", "description": "ISO 8601 date"],
                    "projectId":   ["type": "string"],
                    "goalId":      ["type": "string"],
                ],
            ],
        ],
        [
            "name": "database_update_task",
            "description": "Update a task by id.",
            "parameters": [
                "type": "object",
                "required": ["id"],
                "properties": [
                    "id":          ["type": "string"],
                    "title":       ["type": "string"],
                    "description": ["type": "string"],
                    "status":      ["type": "string"],
                    "priority":    ["type": "string"],
                    "dueAt":       ["type": "string"],
                ],
            ],
        ],
        [
            "name": "database_complete_task",
            "description": "Mark a task as done.",
            "parameters": [
                "type": "object",
                "required": ["id"],
                "properties": ["id": ["type": "string"]],
            ],
        ],
        [
            "name": "database_create_note",
            "description": "Create a free-form note. Returns the new id.",
            "parameters": [
                "type": "object",
                "required": ["title"],
                "properties": [
                    "title": ["type": "string"],
                    "body":  ["type": "string"],
                    "tags":  ["type": "array", "items": ["type": "string"]],
                ],
            ],
        ],
        [
            "name": "database_create_goal",
            "description": "Create a goal. Returns the new id.",
            "parameters": [
                "type": "object",
                "required": ["title"],
                "properties": [
                    "title":       ["type": "string"],
                    "description": ["type": "string"],
                    "status":      ["type": "string", "enum": ["active", "paused", "done"]],
                    "level":       ["type": "string", "enum": ["company", "team", "personal"]],
                ],
            ],
        ],
        [
            "name": "database_find_records",
            "description": "Search records inside a collection. Returns up to 25 matches with title and id.",
            "parameters": [
                "type": "object",
                "required": ["collection", "query"],
                "properties": [
                    "collection": ["type": "string", "description": "Collection name (e.g. tasks, notes, goals)."],
                    "query":      ["type": "string"],
                ],
            ],
        ],
    ]

    // MARK: - Handlers

    private func createTask(_ args: [String: DBJSON]) async throws -> DBJSON {
        guard let title = args["title"]?.stringValue, !title.isEmpty else {
            throw missingArgument("title")
        }
        var data: [String: DBJSON] = [
            "title": .string(title),
            "status": args["status"] ?? .string("todo"),
            "priority": args["priority"] ?? .string("medium"),
        ]
        if let v = args["description"] { data["description"] = v }
        if let v = args["dueAt"]       { data["dueAt"] = v }
        if let v = args["projectId"]   { data["projectId"] = v }
        if let v = args["goalId"]      { data["goalId"] = v }
        let record = try await manager.createRecord(collection: "tasks", data: data)
        return .object(["id": .string(record.id), "title": .string(title)])
    }

    private func updateTask(_ args: [String: DBJSON]) async throws -> DBJSON {
        guard let id = args["id"]?.stringValue, !id.isEmpty else {
            throw missingArgument("id")
        }
        var data: [String: DBJSON] = [:]
        for key in ["title", "description", "status", "priority", "dueAt"] {
            if let v = args[key] { data[key] = v }
        }
        let record = try await manager.updateRecord(collection: "tasks", id: id, data: data)
        return .object(["id": .string(record.id)])
    }

    private func completeTask(_ args: [String: DBJSON]) async throws -> DBJSON {
        guard let id = args["id"]?.stringValue, !id.isEmpty else {
            throw missingArgument("id")
        }
        let record = try await manager.updateRecord(
            collection: "tasks",
            id: id,
            data: ["status": .string("done")]
        )
        return .object(["id": .string(record.id)])
    }

    private func createNote(_ args: [String: DBJSON]) async throws -> DBJSON {
        guard let title = args["title"]?.stringValue, !title.isEmpty else {
            throw missingArgument("title")
        }
        var data: [String: DBJSON] = ["title": .string(title)]
        if let v = args["body"] { data["body"] = v }
        if let v = args["tags"], v.arrayValue != nil { data["tags"] = v }
        let record = try await manager.createRecord(collection: "notes", data: data)
        return .object(["id": .string(record.id)])
    }

    private func createGoal(_ args: [String: DBJSON]) async throws -> DBJSON {
        guard let title = args["title"]?.stringValue, !title.isEmpty else {
            throw missingArgument("title")
        }
        var data: [String: DBJSON] = [
            "title": .string(title),
            "status": args["status"] ?? .string("active"),
            "level": args["level"] ?? .string("personal"),
        ]
        if let v = args["description"] { data["description"] = v }
        let record = try await manager.createRecord(collection: "goals", data: data)
        return .object(["id": .string(record.id)])
    }

    private func findRecords(_ args: [String: DBJSON]) async throws -> DBJSON {
        guard let collection = args["collection"]?.stringValue, !collection.isEmpty else {
            throw missingArgument("collection")
        }
        guard let query = args["query"]?.stringValue, !query.isEmpty else {
            throw missingArgument("query")
        }
        if manager.records(for: collection).isEmpty {
            await manager.refreshRecords(collection: collection)
        }
        let needle = query.lowercased()
        let matches = manager.records(for: collection).filter { record in
            let titleHit = record.titleString.lowercased().contains(needle)
            let textHit = record.data.values.contains { $0.stringValue?.lowercased().contains(needle) == true }
            return titleHit || textHit
        }.prefix(25).map { record in
            DBJSON.object([
                "id": .string(record.id),
                "title": .string(record.titleString),
            ])
        }
        return .array(Array(matches))
    }

    private func missingArgument(_ name: String) -> Error {
        NSError(domain: "DatabaseTools", code: -2, userInfo: [
            NSLocalizedDescriptionKey: "Missing required argument: \(name)",
        ])
    }
}
