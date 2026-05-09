import Foundation

/// What a model can do. A feature picks providers/models by intersecting
/// the capability it needs with the model's declared set.
public enum Capability: String, CaseIterable, Codable, Sendable, Hashable {
    case chat
    case stt
    case tts
    case embeddings
    case imageGen
    case vision
    case toolUse
}
