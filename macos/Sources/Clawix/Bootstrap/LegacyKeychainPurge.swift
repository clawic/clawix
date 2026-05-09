// LEGACY-KEYCHAIN-PURGE-OK
import Foundation
import Security

/// One-shot cleanup of macOS Keychain items left behind by pre-release
/// builds of Clawix that stored daemon admin passwords and provider API
/// keys in `Security.framework`. The shipping app no longer touches the
/// Keychain at all (admin auth uses an ephemeral token written to the
/// daemon's private data dir; provider API keys live in the user's
/// encrypted vault under the "Clawix System" container).
///
/// `SecItemDelete` for an item owned by the same app does not surface a
/// user prompt and silently no-ops if the item is absent, so this runs
/// at every cold start until the gate flag is set.
///
/// This file is the only place in the macOS sources where importing
/// `Security` is allowed; the public hygiene check enforces that via
/// the `LEGACY-KEYCHAIN-PURGE-OK` marker on the first line.
enum LegacyKeychainPurge {
    private static let purgeGateKey = "clawix.legacyKeychainPurged.v1"

    private static var legacyServices: [String] {
        let appServicePrefix = Bundle.main.bundleIdentifier ?? "com.example.clawix.desktop"
        return [
            "\(appServicePrefix).clawjs-database-admin",
            "\(appServicePrefix).clawjs-drive-admin",
            // Enhancement: namespaced per provider; keep in sync with
            // `EnhancementProviderID`.
            "com.clawix.enhancement.openai",
            "com.clawix.enhancement.anthropic",
            "com.clawix.enhancement.groq",
            "com.clawix.enhancement.deepgram",
            "com.clawix.enhancement.ollama",
            "com.clawix.enhancement.mistral",
            "com.clawix.enhancement.xai",
            "com.clawix.enhancement.openrouter",
            "com.clawix.enhancement.custom",
            // Cloud transcription: Groq, Deepgram, Custom OpenAI-compatible.
            "com.clawix.transcription.groq",
            "com.clawix.transcription.deepgram",
            "com.clawix.transcription.custom",
        ]
    }

    static func runOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: purgeGateKey) else { return }
        for service in legacyServices {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
            ]
            SecItemDelete(query as CFDictionary)
        }
        defaults.set(true, forKey: purgeGateKey)
    }
}
