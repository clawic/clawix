import Foundation

public enum CryptoVersion {
    public static let v1: UInt8 = 0x01
    public static let current: UInt8 = v1

    public static func isSupported(_ byte: UInt8) -> Bool {
        byte == v1
    }
}
