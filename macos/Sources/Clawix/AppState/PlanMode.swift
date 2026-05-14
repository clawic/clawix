import Foundation

extension AppState {
    // MARK: - Plan mode

    /// Toggle the global plan-mode flag from the slash command, the
    /// "+" menu, or the composer pill. Wraps in a transaction so any
    /// observer (composer pill, sidebar) updates atomically.
    func togglePlanMode() {
        planMode.toggle()
    }

    /// Pending plan-mode question for the chat the user is currently
    /// looking at, if any. Drives the question card above the composer.
    var currentPendingPlanQuestion: PendingPlanQuestion? {
        guard case let .chat(id) = currentRoute else { return nil }
        return pendingPlanQuestions[id]
    }

    /// Stash a question coming from `item/tool/requestUserInput` so the
    /// chat view can render it. Called from ClawixService.
    func registerPendingPlanQuestion(_ question: PendingPlanQuestion) {
        pendingPlanQuestions[question.chatId] = question
    }

    /// Resolve the JSON-RPC request with the user's answers and clear
    /// the pending state. `answers` maps each question id to the option
    /// labels (or free text) the user picked.
    func submitPlanAnswers(chatId: UUID, answers: [String: [String]]) {
        guard let pending = pendingPlanQuestions[chatId] else { return }
        pendingPlanQuestions[chatId] = nil
        guard let clawix else { return }
        Task { @MainActor in
            await clawix.respondToPlanQuestion(rpcId: pending.rpcId, answers: answers)
        }
    }

    /// Dismiss the question without picking an option. Sends an empty
    /// answers map so the runtime unblocks the turn.
    func dismissPlanQuestion(chatId: UUID) {
        guard let pending = pendingPlanQuestions[chatId] else { return }
        pendingPlanQuestions[chatId] = nil
        let empty: [String: [String]] = Dictionary(
            uniqueKeysWithValues: pending.questions.map { ($0.id, [String]()) }
        )
        guard let clawix else { return }
        Task { @MainActor in
            await clawix.respondToPlanQuestion(rpcId: pending.rpcId, answers: empty)
        }
    }
}
