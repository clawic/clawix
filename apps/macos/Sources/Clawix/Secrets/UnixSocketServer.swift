import Foundation
import Darwin

/// Minimal AF_UNIX SOCK_STREAM listener that accepts connections on a
/// filesystem path and dispatches each accepted file descriptor to the
/// `accept` closure on the caller's queue. Connection lifetime + I/O is
/// owned by the caller; this class only owns the listening socket.
final class UnixSocketServer {

    enum Error: Swift.Error, CustomStringConvertible {
        case socketCreate(errno: Int32)
        case bind(errno: Int32, path: String)
        case listen(errno: Int32)
        case pathTooLong(String)

        var description: String {
            switch self {
            case .socketCreate(let e): return "socket() failed (errno \(e))"
            case .bind(let e, let path): return "bind(\(path)) failed (errno \(e))"
            case .listen(let e): return "listen() failed (errno \(e))"
            case .pathTooLong(let path): return "socket path too long: \(path)"
            }
        }
    }

    private(set) var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let path: String
    private let queue: DispatchQueue
    private let onAccept: (Int32) -> Void

    init(
        path: String,
        queue: DispatchQueue,
        onAccept: @escaping (Int32) -> Void
    ) throws {
        self.path = path
        self.queue = queue
        self.onAccept = onAccept

        let parent = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        unlink(path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { throw Error.socketCreate(errno: errno) }
        self.listenFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < pathCapacity else {
            close(fd)
            self.listenFD = -1
            throw Error.pathTooLong(path)
        }
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { dst in
                _ = strlcpy(dst, path, pathCapacity)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, len)
            }
        }
        if bindResult < 0 {
            let err = errno
            close(fd)
            self.listenFD = -1
            throw Error.bind(errno: err, path: path)
        }
        chmod(path, 0o600)
        if Darwin.listen(fd, 16) < 0 {
            let err = errno
            close(fd)
            self.listenFD = -1
            throw Error.listen(errno: err)
        }
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let conn = Darwin.accept(self.listenFD, nil, nil)
            if conn >= 0 {
                self.onAccept(conn)
            }
        }
        src.setCancelHandler {
            Darwin.close(fd)
        }
        src.resume()
        self.source = src
    }

    func stop() {
        source?.cancel()
        source = nil
        unlink(path)
        listenFD = -1
    }

    deinit {
        stop()
    }
}

/// Read JSON-line frames from a file descriptor, invoking `onLine` for each
/// complete line. Returns when the peer closes or read fails.
enum UnixSocketReader {

    static func readLines(from fd: Int32, onLine: (Data) -> Bool) {
        var buffer = Data()
        let chunkSize = 4096
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        readLoop: while true {
            let n = chunk.withUnsafeMutableBufferPointer { ptr -> Int in
                Darwin.read(fd, ptr.baseAddress, chunkSize)
            }
            if n <= 0 { break }
            buffer.append(chunk, count: n)
            while let nlIndex = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<nlIndex]
                buffer.removeSubrange(...nlIndex)
                let payload = Data(line)
                let cont = onLine(payload)
                if !cont { break readLoop }
            }
        }
    }

    @discardableResult
    static func writeLine(_ data: Data, to fd: Int32) -> Bool {
        var remaining = data
        if !remaining.isEmpty && remaining.last != 0x0A {
            remaining.append(0x0A)
        }
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { buf -> Int in
                Darwin.write(fd, buf.baseAddress, remaining.count)
            }
            if written <= 0 { return false }
            remaining.removeFirst(written)
        }
        return true
    }

    static func close(_ fd: Int32) {
        Darwin.close(fd)
    }
}
