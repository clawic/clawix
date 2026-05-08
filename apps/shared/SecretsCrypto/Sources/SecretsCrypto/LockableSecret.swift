import Foundation

public final class LockableSecret: @unchecked Sendable {

    private let allocation: UnsafeMutableRawBufferPointer
    public let count: Int

    public init(bytes: Data) {
        let n = bytes.count
        let alloc = UnsafeMutableRawBufferPointer.allocate(byteCount: max(n, 1), alignment: 16)
        if n > 0 {
            bytes.copyBytes(to: alloc, count: n)
        } else {
            alloc.storeBytes(of: UInt8(0), as: UInt8.self)
        }
        self.allocation = alloc
        self.count = n
    }

    public static func random(byteCount: Int) -> LockableSecret {
        LockableSecret(bytes: SecureRandom.bytes(byteCount))
    }

    public func withBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
        let view = UnsafeRawBufferPointer(start: allocation.baseAddress, count: count)
        return try body(view)
    }

    public func zero() {
        guard let base = allocation.baseAddress else { return }
        for i in 0..<allocation.count {
            (base + i).storeBytes(of: UInt8(0), as: UInt8.self)
        }
    }

    deinit {
        zero()
        allocation.deallocate()
    }
}
