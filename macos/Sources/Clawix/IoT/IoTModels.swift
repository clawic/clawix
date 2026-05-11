import Foundation

/// Swift mirrors of the clawjs-iot wire types. The canonical sources
/// of truth live in `clawjs/iot/src/server/db.ts` (storage shapes) and
/// `clawjs/iot/src/server/adapters/types.ts` (discovery shapes). When
/// the daemon's schema evolves, update this file alongside.

enum IoTRiskLevel: String, Codable, Equatable {
    case safe
    case caution
    case restricted
}

enum IoTThingKind: String, Codable, Equatable, CaseIterable {
    case light
    case switchKind = "switch"
    case climate
    case cover
    case lock
    case sensor
    case camera
    case media
    case vacuum
    case appliance
    case presence
    case energy
}

struct HomeRecord: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let isDefault: Bool
    let createdAt: String
}

struct AreaRecord: Codable, Identifiable, Equatable {
    let id: String
    let homeId: String
    let label: String
    let aliases: [String]
}

struct ConnectorRecord: Codable, Identifiable, Equatable {
    let id: String
    let homeId: String
    let label: String
    let kind: String
    let status: String
    let capabilities: [String]
}

struct CapabilityRecord: Codable, Identifiable, Equatable {
    let id: String
    let thingId: String
    let key: String
    let label: String?
    let valueType: String?
    let unit: String?
    let observedValue: ToolJSONValue?
    let desiredValue: ToolJSONValue?
    let observedAt: String?
}

struct ThingRecord: Codable, Identifiable, Equatable {
    let id: String
    let homeId: String
    let areaId: String?
    let label: String
    let aliases: [String]
    let kind: IoTThingKind
    let risk: IoTRiskLevel
    let connectorId: String
    let targetRef: String
    let metadata: ToolJSONValue?
    let capabilities: [CapabilityRecord]
}

struct SceneRecord: Codable, Identifiable, Equatable {
    let id: String
    let homeId: String
    let label: String
    let description: String?
    let actions: [IoTActionRequest]
}

struct AutomationRecord: Codable, Identifiable, Equatable {
    let id: String
    let homeId: String
    let label: String
    let enabled: Bool
    let trigger: ToolJSONValue
    let conditions: [ToolJSONValue]
    let actions: [IoTActionRequest]
}

struct ApprovalRecord: Codable, Identifiable, Equatable {
    let id: String
    let homeId: String
    let status: String
    let reason: String
    let action: IoTActionRequest
    let createdAt: String
    let updatedAt: String
}

struct IoTActionRequest: Codable, Equatable {
    var homeId: String?
    var selector: String?
    var area: String?
    var family: String?
    var capability: String?
    var action: String
    var value: ToolJSONValue?
    var targets: [String]?
}

struct IoTActionResult: Codable, Equatable {
    let status: String
    let homeId: String
    let decision: String
    let reasons: [String]
    let updatedAt: String
    let targets: [ActionTarget]
    let capabilityUpdates: [CapabilityUpdate]
    let approvalId: String?

    struct ActionTarget: Codable, Equatable {
        let id: String
        let label: String
        let kind: IoTThingKind
        let areaId: String?
    }

    struct CapabilityUpdate: Codable, Equatable {
        let thingId: String
        let capability: String
        let observedValue: ToolJSONValue?
        let desiredValue: ToolJSONValue?
    }
}

/// Helpers for the UI that need a quick look at the current value of a
/// capability. The store always serializes capability values as JSON,
/// so we walk `ToolJSONValue` to read scalar primitives.
extension CapabilityRecord {
    var observedBool: Bool? { observedValue?.asBool }
    var observedDouble: Double? { observedValue?.asDouble }
    var observedString: String? { observedValue?.asString }
}

extension ToolJSONValue {
    var asBool: Bool? { value as? Bool }
    var asDouble: Double? {
        if let v = value as? Double { return v }
        if let v = value as? Int { return Double(v) }
        return nil
    }
    var asString: String? { value as? String }
    var asDictionary: [String: Any]? { value as? [String: Any] }
}
