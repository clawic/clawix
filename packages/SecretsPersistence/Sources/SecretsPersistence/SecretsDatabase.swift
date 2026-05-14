import Foundation
import GRDB

public final class SecretsDatabase {

    public let dbPool: DatabasePool

    public init(at fileURL: URL) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        self.dbPool = try DatabasePool(path: fileURL.path, configuration: config)
        try Self.migrator.migrate(dbPool)
    }

    public static func openTemporary() throws -> SecretsDatabase {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(ClawixPersistentSurfacePathComponents.temporaryVaultDatabaseName(id: UUID()))
        return try SecretsDatabase(at: tmp)
    }

    public static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.eraseDatabaseOnSchemaChange = false
        SchemaV1.register(in: &m)
        return m
    }

    public func read<T>(_ body: @escaping (Database) throws -> T) throws -> T {
        try dbPool.read(body)
    }

    @discardableResult
    public func write<T>(_ body: @escaping (Database) throws -> T) throws -> T {
        try dbPool.write(body)
    }
}
