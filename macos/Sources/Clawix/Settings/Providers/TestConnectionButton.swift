import AIProviders
import SwiftUI

/// "Test connection" button used in `AddAccountSheet` and
/// `EditAccountSheet`. Builds an `AIClient` from the provided draft
/// and runs `testConnection()`. Result is shown inline.
struct TestConnectionButton: View {
    let providerId: ProviderID
    let apiKey: String
    let baseURL: URL?

    @State private var state: TestState = .idle

    enum TestState: Equatable {
        case idle
        case running
        case ok
        case failed(String)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: run) {
                HStack(spacing: 6) {
                    LucideIcon.auto(stateIcon, size: 11)
                    Text("Test connection")
                        .font(BodyFont.system(size: 12, wght: 600))
                }
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(state == .running)

            statusLabel
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running:
            Text("Testing…")
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
        case .ok:
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Connected")
                    .font(BodyFont.system(size: 11.5, wght: 600))
                    .foregroundColor(Color.green)
            }
        case .failed(let detail):
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text(detail)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(Color.red.opacity(0.9))
                    .lineLimit(2)
            }
        }
    }

    private var stateIcon: String {
        switch state {
        case .ok: return "check"
        case .failed: return "x"
        default: return "zap"
        }
    }

    private func run() {
        state = .running
        Task { @MainActor in
            do {
                let credentials = AIAccountCredentials(apiKey: apiKey)
                let model = ProviderCatalog.defaultModel(for: .chat, in: providerId)
                    ?? ProviderCatalog.definition(for: providerId)?.models.first
                guard let model else {
                    state = .failed("No model available for this provider.")
                    return
                }
                let probeAccount = ProviderAccount(
                    id: UUID(),
                    providerId: providerId,
                    label: "probe",
                    authMethod: .apiKey,
                    isEnabled: true,
                    createdAt: Date(),
                    baseURLOverride: baseURL
                )
                let client: any AIClient
                switch providerId {
                case .openai:
                    client = OpenAIClient(account: probeAccount, model: model, credentials: credentials)
                case .anthropic:
                    client = AnthropicClient(account: probeAccount, model: model, credentials: credentials)
                case .googleGemini:
                    client = GoogleGeminiClient(account: probeAccount, model: model, credentials: credentials)
                case .ollama:
                    client = OllamaClient(account: probeAccount, model: model, credentials: credentials)
                case .githubCopilot:
                    state = .failed("Use 'Sign in with GitHub' to test Copilot.")
                    return
                case .cursor:
                    client = CursorClient(account: probeAccount, model: model, credentials: credentials)
                case .groq, .deepseek, .togetherAI, .glmZhipu, .xai, .mistral,
                     .openrouter, .cerebras, .fireworks, .openAICompatibleCustom:
                    client = OpenAICompatibleClient(account: probeAccount, model: model, credentials: credentials)
                }
                try await client.testConnection()
                state = .ok
            } catch let error as AIClientError {
                state = .failed(error.errorDescription ?? "Failed.")
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
