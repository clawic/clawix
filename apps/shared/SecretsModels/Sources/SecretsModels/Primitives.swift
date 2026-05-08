import Foundation

public typealias EntityID = UUID

public extension UUID {
    static func newID() -> UUID { UUID() }
    var stringValue: String { uuidString }
}

public typealias Timestamp = Int64

public enum Clock {
    public static func now() -> Timestamp {
        Timestamp(Date().timeIntervalSince1970 * 1000)
    }
}

public extension Timestamp {
    var asDate: Date { Date(timeIntervalSince1970: TimeInterval(self) / 1000) }
}
