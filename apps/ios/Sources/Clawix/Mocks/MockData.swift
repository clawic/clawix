import Foundation
import ClawixCore

// Sample state used by SwiftUI #Preview macros and by `CLAWIX_MOCK=1`
// launches so we can iterate on the visual design without a paired
// Mac. Mirrors the kind of inventory a real Codex CLI session produces:
// several chats spread across a handful of working directories so the
// "Projects" section has something to render.

enum MockData {

    static let now = Date()

    static let chats: [WireChat] = [
        WireChat(
            id: "8B46DFE1-B932-48E6-94E7-C86E65F7F18D",
            title: "Refactor authentication module",
            createdAt: now.addingTimeInterval(-3600 * 36),
            isPinned: true,
            isArchived: false,
            hasActiveTurn: true,
            lastMessageAt: now.addingTimeInterval(-180),
            lastMessagePreview: "Sure. Started by analyzing the module's current structure.",
            branch: "main",
            cwd: "/workspace/auth-service"
        ),
        WireChat(
            id: "AE001-AUTH-2",
            title: "Add JWT rotation to login flow",
            createdAt: now.addingTimeInterval(-3600 * 50),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-3600 * 4),
            lastMessagePreview: "Wired up the rotation on every refresh.",
            branch: "feat/jwt-rotation",
            cwd: "/workspace/auth-service"
        ),
        WireChat(
            id: "C0FFEE11-CAFE-4BAB-9B0E-BAB1E7B0FFEE",
            title: "Find round titanium frames on 1688",
            createdAt: now.addingTimeInterval(-3600 * 14),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-3600 * 14),
            lastMessagePreview: "Found a handful of close matches with metal bridge.",
            branch: nil,
            cwd: nil
        ),
        WireChat(
            id: "11111111-2222-3333-4444-555555555555",
            title: "Migrate notes screen to Plus Jakarta Sans",
            createdAt: now.addingTimeInterval(-3600 * 96),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-3600 * 96),
            lastMessagePreview: "Done. Updated 11 widgets and 3 theme files.",
            branch: "feat/typography-pass",
            cwd: "/workspace/notes-app"
        ),
        WireChat(
            id: "NOTES-EMPTY-2",
            title: "Convert NoteCard to glass surface",
            createdAt: now.addingTimeInterval(-3600 * 120),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-3600 * 110),
            lastMessagePreview: "Replaced the solid fill with a Liquid Glass capsule.",
            branch: "feat/glass-cards",
            cwd: "/workspace/notes-app"
        ),
        WireChat(
            id: "22222222-3333-4444-5555-666666666666",
            title: "Investigate flaky session-resume tests",
            createdAt: now.addingTimeInterval(-3600 * 24 * 6),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-3600 * 24 * 6),
            lastMessagePreview: "The race is in setUp; SQLite open vs migration ordering.",
            branch: "main",
            cwd: "/workspace/session-pipeline"
        ),
        WireChat(
            id: "LANDING-1",
            title: "Hero copy A/B for the landing page",
            createdAt: now.addingTimeInterval(-3600 * 8),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-3600 * 7),
            lastMessagePreview: "Variant B reads warmer; ready to ship behind the flag.",
            branch: "main",
            cwd: "/workspace/clawix-landing"
        ),
        WireChat(
            id: "LANDING-2",
            title: "Add download tile to the landing nav",
            createdAt: now.addingTimeInterval(-3600 * 30),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: now.addingTimeInterval(-3600 * 22),
            lastMessagePreview: "Tile added; appcast link still pending review.",
            branch: "feat/download-tile",
            cwd: "/workspace/clawix-landing"
        )
    ]

    static let messages: [WireMessage] = [
        WireMessage(
            id: "m-user-1",
            role: .user,
            content: "Can you help me refactor the authentication module? I want to split the password flow from the OAuth flow without breaking the public API.",
            timestamp: now.addingTimeInterval(-1800)
        ),
        WireMessage(
            id: "m-asst-1",
            role: .assistant,
            content: "Sure. The current `AuthService` mixes both flows in one type. I would split it into `PasswordAuthenticator` and `OAuthAuthenticator`, keeping `AuthService` as a thin facade so callers don't have to change.\n\nFirst pass:\n\n1. Extract the password helpers into their own struct.\n2. Move the OAuth state machine.\n3. Keep `AuthService.signIn(email:password:)` and `AuthService.signIn(provider:)` as public entry points.\n\nWant me to start with step 1?",
            reasoningText: "User asked for a refactor of auth. Need to identify boundaries between password and OAuth flows. Public API surface is the constraint. Plan a 3-step split that keeps callers untouched.",
            streamingFinished: true,
            timestamp: now.addingTimeInterval(-1750)
        ),
        WireMessage(
            id: "m-user-2",
            role: .user,
            content: "Yes, start with step 1.",
            timestamp: now.addingTimeInterval(-180)
        ),
        WireMessage(
            id: "m-asst-2",
            role: .assistant,
            content: "Working on it. Extracting `hashPassword`, `verifyPassword`, and the rate-limit helpers into `PasswordAuthenticator`. Will keep the existing call sites compiling by aliasing in `AuthService`.",
            reasoningText: "Step 1 of the plan. Move password helpers without changing call sites. Rate-limit helper is shared with OAuth; keep it in AuthService for now and revisit after step 2.",
            streamingFinished: false,
            timestamp: now.addingTimeInterval(-90)
        )
    ]
}
