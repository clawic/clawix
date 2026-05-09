import Foundation

/// Generates plausible body text for a path that does not exist on
/// disk and has no hand-crafted fixture under `CLAWIX_FILE_FIXTURE_DIR`.
/// Used only in fixture / dummy mode so tapping a file pill in the
/// showcase always produces something readable instead of "File not
/// found". Templates are short and deterministic; the same path always
/// yields the same content within one launch.
enum FixtureFileSynthesizer {

    static func synthesize(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let basename = url.lastPathComponent
        let stem = (basename as NSString).deletingPathExtension
        let ext = url.pathExtension.lowercased()
        let folder = url.deletingLastPathComponent().lastPathComponent

        switch ext {
        case "sql": return sql(stem: stem, basename: basename)
        case "ts", "tsx": return typescript(stem: stem, basename: basename, isTSX: ext == "tsx")
        case "js", "jsx", "mjs", "cjs": return javascript(stem: stem, basename: basename)
        case "md", "markdown": return markdown(stem: stem, basename: basename, folder: folder)
        case "json": return json(stem: stem, basename: basename)
        case "yml", "yaml": return yaml(stem: stem, basename: basename)
        case "toml": return toml(stem: stem, basename: basename)
        case "py": return python(stem: stem, basename: basename)
        case "rs": return rust(stem: stem, basename: basename)
        case "swift": return swift(stem: stem, basename: basename)
        case "tf": return terraform(stem: stem, basename: basename)
        case "css": return css(stem: stem, basename: basename)
        case "html", "htm": return html(stem: stem, basename: basename)
        case "sh", "bash": return shell(stem: stem, basename: basename)
        case "graphql", "gql": return graphql(stem: stem, basename: basename)
        case "bru": return brunoRequest(stem: stem, basename: basename)
        case "snap": return snapshot(stem: stem, basename: basename)
        case "env", "example": return dotenv(basename: basename)
        case "dockerignore", "gitignore": return ignoreFile(stem: stem)
        default:
            if basename == "Dockerfile" { return dockerfile() }
            if basename == ".dockerignore" { return ignoreFile(stem: "docker") }
            if basename == ".gitignore" { return ignoreFile(stem: "git") }
            if basename == ".env.example" { return dotenv(basename: basename) }
            return generic(basename: basename, stem: stem)
        }
    }

    // MARK: - Templates

    private static func sql(stem: String, basename: String) -> String {
        let table = stem.replacingOccurrences(of: "-", with: "_").lowercased()
        return """
        -- \(basename)
        -- Generated showcase content for the file pill viewer.

        SELECT
            id,
            tenant_id,
            created_at,
            payload
        FROM \(table)
        WHERE created_at >= NOW() - INTERVAL '7 days'
          AND archived_at IS NULL
        ORDER BY created_at DESC
        LIMIT 200;

        -- Supporting index suggestion
        CREATE INDEX IF NOT EXISTS idx_\(table)_recent
            ON \(table) (tenant_id, created_at DESC)
            WHERE archived_at IS NULL;
        """
    }

    private static func typescript(stem: String, basename: String, isTSX: Bool) -> String {
        let symbol = camelCase(stem)
        if isTSX {
            return """
            import { useMemo } from 'react'
            import clsx from 'clsx'

            type \(pascalCase(stem))Props = {
                className?: string
                title?: string
            }

            export function \(pascalCase(stem))({ className, title = '\(stem)' }: \(pascalCase(stem))Props) {
                const tone = useMemo(() => resolveTone(title), [title])
                return (
                    <section className={clsx('rounded-2xl px-4 py-3', tone, className)}>
                        <h2 className="text-sm font-semibold tracking-tight">{title}</h2>
                        <p className="mt-1 text-sm text-zinc-500">Generated showcase tile for {title}.</p>
                    </section>
                )
            }

            function resolveTone(title: string): string {
                return title.length % 2 === 0 ? 'bg-zinc-50' : 'bg-white'
            }
            """
        }
        return """
        // \(basename)
        // Generated showcase content for the file pill viewer.

        export type \(pascalCase(stem))Input = {
            tenantId: string
            payload: Record<string, unknown>
        }

        export async function \(symbol)(input: \(pascalCase(stem))Input): Promise<void> {
            const start = performance.now()
            try {
                await dispatch(input)
            } finally {
                const ms = (performance.now() - start).toFixed(1)
                console.debug(`[\(symbol)] handled tenant=${input.tenantId} in ${ms}ms`)
            }
        }

        async function dispatch({ tenantId, payload }: \(pascalCase(stem))Input): Promise<void> {
            // Replace with the real implementation.
            void tenantId
            void payload
        }
        """
    }

    private static func javascript(stem: String, basename: String) -> String {
        let symbol = camelCase(stem)
        return """
        // \(basename)

        export async function \(symbol)(input) {
            const start = performance.now()
            try {
                await dispatch(input)
            } finally {
                const ms = (performance.now() - start).toFixed(1)
                console.debug(`[\(symbol)] handled in ${ms}ms`)
            }
        }

        async function dispatch(input) {
            return input
        }
        """
    }

    private static func markdown(stem: String, basename: String, folder: String) -> String {
        let title = humanize(stem)
        return """
        # \(title)

        > Showcase preview · \(folder)/\(basename)

        ## Overview

        This document is a generated placeholder for **\(basename)** so the file
        viewer always has something readable in dummy mode. In a real project
        the body would describe the rationale, decisions, and follow-ups
        captured during the conversation.

        ## Highlights

        - Context: motivations, constraints, and the team that owns the change
        - Decision log: alternatives considered and why each was rejected
        - Rollout: feature flags, dark launches, and the canary checklist
        - Aftermath: dashboards to watch and the runbook for rollback

        ## Open questions

        1. What metric tells us this landed?
        2. Who owns the on-call follow-up next quarter?
        3. Where does the deprecation timeline live?
        """
    }

    private static func json(stem: String, basename: String) -> String {
        if basename == "package.json" {
            return """
            {
                "name": "\(stem.lowercased())",
                "version": "1.4.2",
                "private": true,
                "scripts": {
                    "dev": "vite",
                    "build": "vite build",
                    "lint": "eslint --max-warnings=0 src",
                    "test": "vitest run"
                },
                "dependencies": {
                    "react": "^18.2.0",
                    "react-dom": "^18.2.0"
                },
                "devDependencies": {
                    "typescript": "^5.4.0",
                    "vite": "^5.2.0",
                    "vitest": "^1.5.0"
                }
            }
            """
        }
        if basename == "tsconfig.json" {
            return """
            {
                "compilerOptions": {
                    "target": "ES2022",
                    "module": "ESNext",
                    "moduleResolution": "Bundler",
                    "strict": true,
                    "jsx": "react-jsx",
                    "skipLibCheck": true,
                    "noUncheckedIndexedAccess": true,
                    "isolatedModules": true,
                    "esModuleInterop": true
                },
                "include": ["src", "test"]
            }
            """
        }
        return """
        {
            "name": "\(stem)",
            "generated": true,
            "entries": [
                { "id": "a1", "label": "First entry", "weight": 0.42 },
                { "id": "b2", "label": "Second entry", "weight": 0.31 },
                { "id": "c3", "label": "Third entry", "weight": 0.27 }
            ]
        }
        """
    }

    private static func yaml(stem: String, basename: String) -> String {
        return """
        # \(basename)
        name: \(stem)
        generated: true
        replicas: 3
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "100m"
            memory: "128Mi"
        env:
          - name: LOG_LEVEL
            value: info
          - name: REGION
            value: eu-west-1
        """
    }

    private static func toml(stem: String, basename: String) -> String {
        return """
        # \(basename)
        [package]
        name = "\(stem)"
        version = "0.4.0"
        edition = "2021"

        [dependencies]
        serde = { version = "1", features = ["derive"] }
        tokio = { version = "1.36", features = ["full"] }
        tracing = "0.1"
        """
    }

    private static func python(stem: String, basename: String) -> String {
        let symbol = snakeCase(stem)
        return """
        \"\"\"\(basename)

        Generated showcase content for the file pill viewer.
        \"\"\"

        from __future__ import annotations

        from dataclasses import dataclass
        from typing import Iterable


        @dataclass(frozen=True)
        class \(pascalCase(stem))Input:
            tenant_id: str
            rows: Iterable[dict]


        def \(symbol)(payload: \(pascalCase(stem))Input) -> int:
            count = 0
            for row in payload.rows:
                count += 1 if row.get("ok") else 0
            return count
        """
    }

    private static func rust(stem: String, basename: String) -> String {
        let symbol = snakeCase(stem)
        return """
        //! \(basename)

        use serde::{Deserialize, Serialize};

        #[derive(Debug, Clone, Serialize, Deserialize)]
        pub struct \(pascalCase(stem))Input {
            pub tenant_id: String,
            pub payload: serde_json::Value,
        }

        pub async fn \(symbol)(input: \(pascalCase(stem))Input) -> anyhow::Result<()> {
            tracing::debug!(tenant_id = %input.tenant_id, "handling \(symbol)");
            Ok(())
        }
        """
    }

    private static func swift(stem: String, basename: String) -> String {
        return """
        // \(basename)

        import Foundation

        struct \(pascalCase(stem)) {
            let tenantId: String
            let payload: [String: Any]

            func run() async throws {
                // Replace with the real implementation.
            }
        }
        """
    }

    private static func terraform(stem: String, basename: String) -> String {
        return """
        # \(basename)

        terraform {
          required_version = ">= 1.6.0"
        }

        resource "aws_s3_bucket" "\(snakeCase(stem))" {
          bucket = "showcase-\(snakeCase(stem))"

          tags = {
            owner = "platform"
            env   = "staging"
          }
        }

        output "\(snakeCase(stem))_arn" {
          value = aws_s3_bucket.\(snakeCase(stem)).arn
        }
        """
    }

    private static func css(stem: String, basename: String) -> String {
        return """
        /* \(basename) */

        :root {
            --\(snakeCase(stem, separator: "-"))-bg: #f8f8f8;
            --\(snakeCase(stem, separator: "-"))-fg: #111;
        }

        .\(snakeCase(stem, separator: "-")) {
            background: var(--\(snakeCase(stem, separator: "-"))-bg);
            color: var(--\(snakeCase(stem, separator: "-"))-fg);
            border-radius: 12px;
            padding: 12px 16px;
        }
        """
    }

    private static func html(stem: String, basename: String) -> String {
        return """
        <!doctype html>
        <html lang="en">
            <head>
                <meta charset="utf-8" />
                <title>\(humanize(stem))</title>
            </head>
            <body>
                <main>
                    <h1>\(humanize(stem))</h1>
                    <p>Generated showcase content for the file pill viewer.</p>
                </main>
            </body>
        </html>
        """
    }

    private static func shell(stem: String, basename: String) -> String {
        return """
        #!/usr/bin/env bash
        # \(basename)
        set -euo pipefail

        HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        cd "$HERE"

        echo "running \(stem)..."
        # Replace with the real script body.
        """
    }

    private static func graphql(stem: String, basename: String) -> String {
        return """
        # \(basename)

        type Query {
            \(camelCase(stem)): [\(pascalCase(stem))!]!
        }

        type \(pascalCase(stem)) {
            id: ID!
            createdAt: String!
            label: String!
        }
        """
    }

    private static func brunoRequest(stem: String, basename: String) -> String {
        return """
        meta {
          name: \(humanize(stem))
          type: http
          seq: 1
        }

        post {
          url: {{baseUrl}}/v1/\(snakeCase(stem, separator: "-"))
          body: json
          auth: bearer
        }

        body:json {
          {
            "tenantId": "{{tenantId}}",
            "payload": { "label": "\(stem)" }
          }
        }
        """
    }

    private static func snapshot(stem: String, basename: String) -> String {
        return """
        // \(basename)
        // Vitest snapshot.

        exports[`\(stem) renders the happy path 1`] = `
        <section
          class="rounded-2xl px-4 py-3 bg-white"
        >
          <h2
            class="text-sm font-semibold tracking-tight"
          >
            \(humanize(stem))
          </h2>
          <p
            class="mt-1 text-sm text-zinc-500"
          >
            Generated showcase tile.
          </p>
        </section>
        `
        """
    }

    private static func dotenv(basename: String) -> String {
        return """
        # \(basename)
        DATABASE_URL="postgres://user:pass@localhost:5432/app"
        REDIS_URL="redis://localhost:6379/0"
        SESSION_SECRET="change-me"
        LOG_LEVEL="info"
        """
    }

    private static func ignoreFile(stem: String) -> String {
        return """
        # \(stem) ignore
        node_modules/
        dist/
        build/
        .env
        .env.*
        .DS_Store
        coverage/
        *.log
        """
    }

    private static func dockerfile() -> String {
        return """
        # syntax=docker/dockerfile:1.6
        FROM node:20-bookworm-slim AS deps
        WORKDIR /app
        COPY package.json package-lock.json ./
        RUN npm ci --omit=dev

        FROM node:20-bookworm-slim AS runtime
        WORKDIR /app
        COPY --from=deps /app/node_modules ./node_modules
        COPY . .
        ENV NODE_ENV=production
        EXPOSE 3000
        CMD ["node", "dist/server.js"]
        """
    }

    private static func generic(basename: String, stem: String) -> String {
        return """
        \(basename)
        \(String(repeating: "─", count: max(basename.count, 8)))

        Generated showcase content for the file pill viewer.

        This file is a placeholder so the iPhone (and the macOS sidebar)
        always render something instead of a "File not found" empty state
        when the demo dataset references a path that does not exist on
        this Mac. Drop a real file at
        $CLAWIX_FILE_FIXTURE_DIR/\(stem) to override.
        """
    }

    // MARK: - Helpers

    private static func humanize(_ s: String) -> String {
        let cleaned = s
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return cleaned
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func pascalCase(_ s: String) -> String {
        let parts = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let joined = parts
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined()
        return joined.isEmpty ? "Demo" : joined
    }

    private static func camelCase(_ s: String) -> String {
        let pascal = pascalCase(s)
        return pascal.prefix(1).lowercased() + pascal.dropFirst()
    }

    private static func snakeCase(_ s: String, separator: String = "_") -> String {
        let parts = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        var pieces: [String] = []
        for raw in parts {
            var current = ""
            for ch in raw {
                if ch.isUppercase, !current.isEmpty {
                    pieces.append(current.lowercased())
                    current = ""
                }
                current.append(ch)
            }
            if !current.isEmpty { pieces.append(current.lowercased()) }
        }
        let joined = pieces.joined(separator: separator)
        return joined.isEmpty ? "demo" : joined
    }
}
