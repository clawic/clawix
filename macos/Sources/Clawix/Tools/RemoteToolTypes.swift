import Foundation

/// Swift mirrors of the JSON envelopes the daemon exposes through
/// `GET /v1/tools/list` and `POST /v1/tools/:id/invoke`. The canonical
/// source of truth lives in `@clawjs/core/agent_tools.ts` and in the
/// per-feature daemons (currently `clawjs/iot/src/server/tools.ts`).
/// Keep this file aligned when those shapes change.

/// One LLM-callable verb published by a feature on the daemon.
struct RemoteToolDescriptor: Codable, Identifiable, Equatable {
    /// Stable dot-separated identifier, e.g. `iot.things.list`.
    let id: String
    let title: String
    let description: String
    let domain: String
    let sourceFeature: String
    let parameters: ParametersSchema
    let riskLevel: RiskLevel
    let requiresApproval: Bool?
    let version: String?

    enum RiskLevel: String, Codable, Equatable {
        case safe
        case reversible
        case sensitive
        case catastrophic
    }

    /// Loose JSON Schema object. The Swift side keeps it opaque (a
    /// stringly-typed dictionary) so feature packages can evolve their
    /// parameter shapes without forcing a client rebuild.
    struct ParametersSchema: Codable, Equatable {
        let type: String
        let properties: [String: PropertyDescriptor]?
        let required: [String]?
        let additionalProperties: Bool?
        let description: String?
    }

    struct PropertyDescriptor: Codable, Equatable {
        let type: String?
        let description: String?
        let enumeration: [String]?

        private enum CodingKeys: String, CodingKey {
            case type
            case description
            case enumeration = "enum"
        }
    }
}

/// Wire shape returned by `GET /v1/tools/list`.
struct RemoteToolCatalog: Codable, Equatable {
    let generatedAt: String
    let tools: [RemoteToolDescriptor]
}

/// Wire shape returned by `POST /v1/tools/:id/invoke`. Mirrors
/// `AgentToolInvocationResult` from `@clawjs/core/agent_tools.ts`.
struct RemoteToolInvocationResult: Codable, Equatable {
    let ok: Bool
    let value: ToolJSONValue?
    let error: RemoteToolInvocationError?
    let invocationId: String?
    let durationMs: Int?
}

struct RemoteToolInvocationError: Codable, Equatable {
    let code: String
    let message: String
    let detail: ToolJSONValue?
}

/// Minimal type-erased JSON wrapper for free-form payloads we forward
/// to the model without inspecting. SwiftUI consumers that need the raw
/// structure read `.value` (Any) and downcast as appropriate.
struct ToolJSONValue: Codable, Equatable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([ToolJSONValue].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: ToolJSONValue].self) {
            value = dict.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { ToolJSONValue($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { ToolJSONValue($0) })
        default:
            try container.encodeNil()
        }
    }

    static func == (lhs: ToolJSONValue, rhs: ToolJSONValue) -> Bool {
        switch (lhs.value, rhs.value) {
        case (is NSNull, is NSNull): return true
        case (let l as Bool, let r as Bool): return l == r
        case (let l as Int, let r as Int): return l == r
        case (let l as Double, let r as Double): return l == r
        case (let l as String, let r as String): return l == r
        case (let l as [Any], let r as [Any]):
            return l.map(ToolJSONValue.init) == r.map(ToolJSONValue.init)
        case (let l as [String: Any], let r as [String: Any]):
            return l.mapValues(ToolJSONValue.init) == r.mapValues(ToolJSONValue.init)
        default:
            return false
        }
    }
}
