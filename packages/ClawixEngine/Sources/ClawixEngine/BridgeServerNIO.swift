#if !canImport(Network)
import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
import ClawixCore

/// Linux-side WebSocket server. Same public API as the Apple-side
/// `BridgeServer` so calling sites are platform-agnostic. Uses SwiftNIO
/// instead of `Network.framework`. Bonjour publishing is delegated to the
/// surrounding service (Avahi via `dbus`); the listener itself just
/// accepts WS upgrades on the requested TCP port.
@MainActor
public final class BridgeServer {
    private weak var host: EngineHost?
    private let port: Int
    private let pairing: PairingService
    private let publishBonjour: Bool
    private let group: MultiThreadedEventLoopGroup
    private var channel: Channel?
    private var bus: BridgeBus?
    private var sessions: [BridgeSession] = []
    public private(set) var isRunning: Bool = false

    public init(
        host: EngineHost,
        port: UInt16 = 24080,
        pairing: PairingService = .shared,
        publishBonjour: Bool = true
    ) {
        self.host = host
        self.port = Int(port)
        self.pairing = pairing
        self.publishBonjour = publishBonjour
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    deinit {
        try? group.syncShutdownGracefully()
    }

    public func start() {
        guard !isRunning, let host else { return }
        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { (channel, head) in
                channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { [weak self] channel, _ in
                channel.eventLoop.makeSucceededFuture(()).flatMap {
                    self?.installSessionHandler(on: channel) ?? channel.eventLoop.makeSucceededFuture(())
                }
            }
        )

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let httpHandler = HTTPHandler()
                let config: NIOHTTPServerUpgradeConfiguration = (
                    upgraders: [upgrader],
                    completionHandler: { _ in
                        channel.pipeline.removeHandler(httpHandler, promise: nil)
                    }
                )
                return channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: config).flatMap {
                    channel.pipeline.addHandler(httpHandler)
                }
            }

        do {
            channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
            let bus = BridgeBus(host: host)
            bus.startObserving { [weak self] frame in
                self?.broadcast(frame)
            }
            self.bus = bus
            isRunning = true
            BridgeLog.write("server-listening tcp/\(port) bonjour=\(publishBonjour) backend=nio")
        } catch {
            BridgeLog.write("server-listen-failed \(error)")
        }
    }

    public func stop() {
        try? channel?.close().wait()
        channel = nil
        bus?.stop()
        bus = nil
        for session in sessions {
            session.close(.normalClosure)
        }
        sessions.removeAll()
        BridgeStats.shared.reset()
        isRunning = false
    }

    private func installSessionHandler(on channel: Channel) -> EventLoopFuture<Void> {
        let promise = channel.eventLoop.makePromise(of: Void.self)
        Task { @MainActor in
            guard let host, let bus else {
                channel.close(promise: nil)
                promise.succeed(())
                return
            }
            let session = BridgeSession(
                channel: channel,
                host: host,
                bus: bus,
                pairing: pairing,
                onTerminated: { [weak self] sid in
                    Task { @MainActor in
                        self?.sessions.removeAll { $0.id == sid }
                    }
                }
            )
            sessions.append(session)
            let handler = BridgeWebSocketHandler(session: session)
            _ = channel.pipeline.addHandler(handler)
            session.start()
            promise.succeed(())
        }
        return promise.futureResult
    }

    private func broadcast(_ frame: BridgeFrame) {
        for session in sessions where session.isAuthenticated {
            session.send(frame)
        }
    }
}

/// HTTP no-op handler so unupgraded connections receive a 404 and close.
private final class HTTPHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        guard case .end = part else { return }
        var headers = HTTPHeaders()
        headers.add(name: "Content-Length", value: "0")
        headers.add(name: "Connection", value: "close")
        let head = HTTPResponseHead(
            version: HTTPVersion(major: 1, minor: 1),
            status: .notFound,
            headers: headers
        )
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        context.close(promise: nil)
    }
}

/// Bridges raw NIO WebSocket frames into the `BridgeSession` actor.
final class BridgeWebSocketHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private weak var session: BridgeSession?
    private var awaitingClose = false
    private var fragmentBuffer = ByteBufferAllocator().buffer(capacity: 0)

    init(session: BridgeSession) {
        self.session = session
    }

    func handlerAdded(context: ChannelHandlerContext) {
        Task { @MainActor [weak self] in
            self?.session?.attach(channel: context.channel)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        case .connectionClose:
            awaitingClose = true
            let close = WebSocketFrame(fin: true, opcode: .connectionClose, data: frame.unmaskedData)
            context.write(wrapOutboundOut(close)).whenComplete { _ in
                context.close(promise: nil)
            }
        case .text, .binary:
            var data = frame.unmaskedData
            if !frame.fin {
                fragmentBuffer.writeBuffer(&data)
                return
            }
            if fragmentBuffer.readableBytes > 0 {
                fragmentBuffer.writeBuffer(&data)
                let payload = fragmentBuffer.readData(length: fragmentBuffer.readableBytes) ?? Data()
                fragmentBuffer.clear()
                deliver(payload)
            } else {
                let payload = data.readData(length: data.readableBytes) ?? Data()
                deliver(payload)
            }
        case .continuation:
            var data = frame.unmaskedData
            fragmentBuffer.writeBuffer(&data)
            if frame.fin {
                let payload = fragmentBuffer.readData(length: fragmentBuffer.readableBytes) ?? Data()
                fragmentBuffer.clear()
                deliver(payload)
            }
        default:
            break
        }
    }

    private func deliver(_ data: Data) {
        guard !data.isEmpty, let session else { return }
        Task { @MainActor in
            session.handleInbound(data: data)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        BridgeLog.write("ws-error \(error)")
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        Task { @MainActor [weak self] in
            self?.session?.terminateExternal()
        }
    }
}
#endif
