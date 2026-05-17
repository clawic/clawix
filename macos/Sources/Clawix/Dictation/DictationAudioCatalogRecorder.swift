import Foundation
import ClawixCore
import ClawixEngine

@MainActor
enum DictationAudioCatalogRecorder {
    static func register(
        record: TranscriptionRecord,
        samples: [Float],
        processedText: String,
        originalText: String,
        model: DictationModel?,
        language: String?,
        enhancementProvider: String?
    ) async {
        guard let data = DictationAudioStorage.wavData(samples: samples),
              let client = AudioCatalogBootstrap.shared.currentClient
        else { return }

        let metadata: [String: Any?] = [
            "originalText": originalText,
            "powerModeId": record.powerModeId,
            "enhancementProvider": enhancementProvider,
            "costUSD": record.costUSD,
        ]
        let metadataData = try? JSONSerialization.data(
            withJSONObject: metadata.compactMapValues { $0 },
            options: [.sortedKeys]
        )
        _ = try? await AudioCatalogRegistration.register(
            client: client,
            id: record.id,
            kind: WireAudioKind.dictation.rawValue,
            appId: "clawix",
            originActor: WireAudioOriginActor.user.rawValue,
            audioData: data,
            mimeType: "audio/wav",
            metadataJson: metadataData.flatMap { String(data: $0, encoding: .utf8) },
            transcript: .init(
                text: processedText,
                role: "transcription",
                provider: model?.rawValue,
                language: language
            )
        )
    }
}
