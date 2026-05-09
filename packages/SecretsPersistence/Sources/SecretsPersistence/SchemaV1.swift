import Foundation
import GRDB

enum SchemaV1 {

    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1") { db in
            try db.execute(sql: vaultMeta)
            try db.execute(sql: accounts)
            try db.execute(sql: accountsSeed)
            try db.execute(sql: vaults)
            try db.execute(sql: secrets)
            try db.execute(sql: secretVersions)
            try db.execute(sql: secretFields)
            try db.execute(sql: secretNotes)
            try db.execute(sql: attachments)
            try db.execute(sql: agentGrants)
            try db.execute(sql: auditEvents)
            try db.execute(sql: secretsSettings)
        }
    }

    static let vaultMeta = """
        CREATE TABLE vaultMeta (
            key TEXT PRIMARY KEY NOT NULL,
            value BLOB NOT NULL
        );
        """

    static let accounts = """
        CREATE TABLE accounts (
            id INTEGER PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            createdAt INTEGER NOT NULL
        );
        """

    static let accountsSeed = """
        INSERT INTO accounts (id, name, createdAt)
        VALUES (0, 'Default', CAST(strftime('%s','now') AS INTEGER) * 1000);
        """

    static let vaults = """
        CREATE TABLE vaults (
            id TEXT PRIMARY KEY NOT NULL,
            accountId INTEGER NOT NULL DEFAULT 0 REFERENCES accounts(id),
            name TEXT NOT NULL,
            icon TEXT,
            color TEXT,
            sortOrder INTEGER NOT NULL DEFAULT 0,
            trashedAt INTEGER,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
        );
        CREATE INDEX vaults_accountId ON vaults(accountId);
        """

    static let secrets = """
        CREATE TABLE secrets (
            id TEXT PRIMARY KEY NOT NULL,
            accountId INTEGER NOT NULL DEFAULT 0 REFERENCES accounts(id),
            vaultId TEXT NOT NULL REFERENCES vaults(id),
            kind TEXT NOT NULL,
            brandPreset TEXT,
            internalName TEXT NOT NULL,
            title TEXT NOT NULL,
            wrappedItemKey BLOB NOT NULL,
            currentVersionId TEXT NOT NULL,
            isArchived INTEGER NOT NULL DEFAULT 0,
            isCompromised INTEGER NOT NULL DEFAULT 0,
            isLocked INTEGER NOT NULL DEFAULT 0,
            readOnly INTEGER NOT NULL DEFAULT 0,
            trashedAt INTEGER,
            allowedHostsJson TEXT,
            allowedHeadersJson TEXT,
            allowInUrl INTEGER NOT NULL DEFAULT 0,
            allowInBody INTEGER NOT NULL DEFAULT 0,
            allowInEnv INTEGER NOT NULL DEFAULT 1,
            allowInsecureTransport INTEGER NOT NULL DEFAULT 0,
            allowLocalNetwork INTEGER NOT NULL DEFAULT 0,
            allowedAgentsJson TEXT,
            approvalMode TEXT NOT NULL DEFAULT 'auto',
            approvalWindowMinutes INTEGER,
            ttlExpiresAt INTEGER,
            maxUses INTEGER,
            useCount INTEGER NOT NULL DEFAULT 0,
            rotationReminderDays INTEGER,
            lastRotatedAt INTEGER,
            redactionLabel TEXT,
            clipboardClearSeconds INTEGER NOT NULL DEFAULT 30,
            auditRetentionDays INTEGER,
            tagsJson TEXT,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL,
            lastUsedAt INTEGER,
            UNIQUE(accountId, internalName)
        );
        CREATE INDEX secrets_vaultId ON secrets(vaultId);
        CREATE INDEX secrets_kind ON secrets(kind);
        CREATE INDEX secrets_internalName ON secrets(accountId, internalName);
        CREATE INDEX secrets_trashedAt ON secrets(trashedAt);
        """

    static let secretVersions = """
        CREATE TABLE secretVersions (
            id TEXT PRIMARY KEY NOT NULL,
            secretId TEXT NOT NULL REFERENCES secrets(id) ON DELETE CASCADE,
            versionNumber INTEGER NOT NULL,
            reason TEXT NOT NULL,
            diffSummary TEXT,
            createdAt INTEGER NOT NULL,
            createdBy TEXT NOT NULL,
            UNIQUE(secretId, versionNumber)
        );
        CREATE INDEX secretVersions_secret ON secretVersions(secretId, versionNumber DESC);
        """

    static let secretFields = """
        CREATE TABLE secretFields (
            id TEXT PRIMARY KEY NOT NULL,
            secretId TEXT NOT NULL REFERENCES secrets(id) ON DELETE CASCADE,
            versionId TEXT NOT NULL REFERENCES secretVersions(id) ON DELETE CASCADE,
            fieldName TEXT NOT NULL,
            fieldKind TEXT NOT NULL,
            placement TEXT NOT NULL DEFAULT 'none',
            isSecret INTEGER NOT NULL,
            isConcealed INTEGER NOT NULL DEFAULT 1,
            publicValue TEXT,
            valueCiphertext BLOB,
            otpPeriod INTEGER,
            otpDigits INTEGER,
            otpAlgorithm TEXT,
            sortOrder INTEGER NOT NULL DEFAULT 0,
            UNIQUE(versionId, fieldName)
        );
        CREATE INDEX secretFields_secretVersion ON secretFields(secretId, versionId);
        """

    static let secretNotes = """
        CREATE TABLE secretNotes (
            secretId TEXT NOT NULL REFERENCES secrets(id) ON DELETE CASCADE,
            versionId TEXT NOT NULL REFERENCES secretVersions(id) ON DELETE CASCADE,
            ciphertext BLOB,
            PRIMARY KEY (secretId, versionId)
        );
        """

    static let attachments = """
        CREATE TABLE attachments (
            id TEXT PRIMARY KEY NOT NULL,
            secretId TEXT NOT NULL REFERENCES secrets(id) ON DELETE CASCADE,
            versionId TEXT NOT NULL REFERENCES secretVersions(id) ON DELETE CASCADE,
            filename TEXT NOT NULL,
            mimeType TEXT,
            size INTEGER NOT NULL,
            wrappedAttachmentKey BLOB NOT NULL,
            ciphertext BLOB NOT NULL,
            sortOrder INTEGER NOT NULL DEFAULT 0,
            createdAt INTEGER NOT NULL
        );
        CREATE INDEX attachments_secretVersion ON attachments(secretId, versionId);
        """

    static let agentGrants = """
        CREATE TABLE agentGrants (
            id TEXT PRIMARY KEY NOT NULL,
            accountId INTEGER NOT NULL DEFAULT 0 REFERENCES accounts(id),
            agent TEXT NOT NULL,
            secretId TEXT NOT NULL REFERENCES secrets(id) ON DELETE CASCADE,
            capability TEXT NOT NULL,
            scopeJson TEXT,
            reason TEXT NOT NULL,
            tokenHash BLOB NOT NULL,
            createdAt INTEGER NOT NULL,
            expiresAt INTEGER NOT NULL,
            revokedAt INTEGER,
            usedCount INTEGER NOT NULL DEFAULT 0,
            lastUsedAt INTEGER
        );
        CREATE INDEX agentGrants_secret ON agentGrants(secretId);
        CREATE INDEX agentGrants_active ON agentGrants(expiresAt, revokedAt);
        """

    static let auditEvents = """
        CREATE TABLE auditEvents (
            id TEXT PRIMARY KEY NOT NULL,
            accountId INTEGER NOT NULL DEFAULT 0 REFERENCES accounts(id),
            secretId TEXT,
            vaultId TEXT,
            versionId TEXT,
            kind TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            source TEXT NOT NULL,
            success INTEGER,
            deviceId TEXT,
            sessionId TEXT,
            wrappedEventKey BLOB NOT NULL,
            payloadCiphertext BLOB NOT NULL,
            prevHash BLOB NOT NULL,
            selfHash BLOB NOT NULL,
            CHECK (length(prevHash) = 32 AND length(selfHash) = 32)
        );
        CREATE INDEX auditEvents_secretTs ON auditEvents(secretId, timestamp DESC);
        CREATE INDEX auditEvents_kindTs ON auditEvents(kind, timestamp DESC);
        CREATE INDEX auditEvents_ts ON auditEvents(timestamp DESC);
        CREATE INDEX auditEvents_session ON auditEvents(sessionId, timestamp);
        """

    static let secretsSettings = """
        CREATE TABLE secretsSettings (
            accountId INTEGER NOT NULL DEFAULT 0 REFERENCES accounts(id),
            key TEXT NOT NULL,
            value TEXT NOT NULL,
            PRIMARY KEY (accountId, key)
        );
        """
}
