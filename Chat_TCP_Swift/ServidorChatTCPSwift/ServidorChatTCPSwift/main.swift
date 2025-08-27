//
//  main.swift
//  ServidorChatTCPSwift
//
//  Created by Luccas Carneiro on 26/08/25.
//

import Foundation
import NIO
import NIOConcurrencyHelpers

// -------- IP local IPv4 (não-loopback) ----------
func firstNonLoopbackIPv4() -> String {
    var address = "127.0.0.1"
    var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return address }
    defer { freeifaddrs(ifaddrPtr) }
    for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let ifa = ptr.pointee
        if ifa.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
            var addr = sockaddr_in()
            memcpy(&addr, ifa.ifa_addr, MemoryLayout<sockaddr_in>.size)
            let ip = withUnsafePointer(to: &addr.sin_addr) {
                $0.withMemoryRebound(to: UInt8.self, capacity: 4) { p in
                    "\(p[0]).\(p[1]).\(p[2]).\(p[3])"
                }
            }
            if ip != "127.0.0.1" { address = ip; break }
        }
    }
    return address
}

// --------- Modelo/Estado ----------
struct ClientInfo {
    let channel: Channel
    let apelido: String
    let ip: String
    let portaPrivada: Int
}

final class ServerState {
    private let lock = NIOLock()
    private var byChannel: [ObjectIdentifier: ClientInfo] = [:]
    private var byNick: [String: ObjectIdentifier] = [:]

    func add(_ info: ClientInfo) {
        lock.withLock {
            let id = ObjectIdentifier(info.channel)
            byChannel[id] = info
            byNick[info.apelido.lowercased()] = id
        }
    }
    func remove(channel: Channel) {
        lock.withLock {
            let id = ObjectIdentifier(channel)
            if let info = byChannel.removeValue(forKey: id) {
                byNick.removeValue(forKey: info.apelido.lowercased())
            }
        }
    }
    func count() -> Int { lock.withLock { byChannel.count } }
    func listCSV() -> String {
        lock.withLock {
            byChannel.values
                .map { "\($0.apelido);\($0.ip);\($0.portaPrivada)" }
                .joined(separator: "\n") + "\n"
        }
    }
    func findChannel(nick: String) -> Channel? {
        lock.withLock {
            guard let id = byNick[nick.lowercased()] else { return nil }
            return byChannel[id]?.channel
        }
    }
    func all() -> [ClientInfo] { lock.withLock { Array(byChannel.values) } }
}

// -------- Handlers ----------
final class ChatHandler: ChannelInboundHandler {
    typealias InboundIn  = ByteBuffer
    typealias OutboundOut = ByteBuffer   // <= Corrige erro 'Never'

    private let state: ServerState
    private let startTime: Date
    private var handshaked = false
    private var apelido = ""
    private var portaPrivada = 0
    private var ipRemoto = ""
    private var hsBuffer = "" // handshake sem newline

    init(state: ServerState, startTime: Date) {
        self.state = state
        self.startTime = startTime
    }

    func channelActive(context: ChannelHandlerContext) {
        ipRemoto = context.remoteAddress?.ipAddress ?? "0.0.0.0"
    }

    func channelInactive(context: ChannelHandlerContext) {
        state.remove(channel: context.channel)
        print("Cliente desconectado. Total: \(state.count())")
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buf = unwrapInboundIn(data)
        guard let chunk = buf.readString(length: buf.readableBytes), !chunk.isEmpty else { return }

        if !handshaked {
            hsBuffer += chunk
            // Espera "apelido;portaPrivada" (sem \n)
            if let semi = hsBuffer.firstIndex(of: ";") {
                let nick = String(hsBuffer[..<semi])
                let rest = String(hsBuffer[hsBuffer.index(after: semi)...])
                if let porta = Int(rest) {
                    apelido = nick
                    portaPrivada = porta
                    state.add(.init(channel: context.channel, apelido: apelido, ip: ipRemoto, portaPrivada: portaPrivada))
                    handshaked = true
                    print("[\(ts())] Novo usuário: \(apelido) (\(ipRemoto):\(portaPrivada))")
                }
            }
            return
        }

        handleMessage(context: context, msg: chunk)
    }

    private func handleMessage(context: ChannelHandlerContext, msg: String) {
        let mensagem = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        switch true {
        case mensagem == "/count":
            write(context, "Usuarios Conectados: \(state.count())")
        case mensagem == "/lista":
            write(context, state.listCSV())
        case mensagem.hasPrefix("/desconectar "):
            let nick = String(mensagem.dropFirst("/desconectar".count)).trimmingCharacters(in: .whitespaces)
            if let ch = state.findChannel(nick: nick) {
                ch.close(promise: nil)
                write(context, "Usuário \(nick) desconectado com sucesso.")
                print("Usuário \(nick) desconectado via comando.")
            } else {
                write(context, "Usuário \(nick) não encontrado.")
            }
        case mensagem == "/status":
            let up = Int(Date().timeIntervalSince(startTime))
            write(context, "Servidor online - Usuários conectados: \(state.count()) - Uptime: \(up)s")
        default:
            print("Mensagem: \(mensagem)")
            broadcast(mensagem)
        }
    }

    private func broadcast(_ text: String) {
        for c in state.all() {
            var out = c.channel.allocator.buffer(capacity: text.utf8.count)
            out.writeString(text)
            _ = c.channel.writeAndFlush(out)
        }
    }

    private func write(_ ctx: ChannelHandlerContext, _ text: String) {
        var out = ctx.channel.allocator.buffer(capacity: text.utf8.count)
        out.writeString(text)
        ctx.writeAndFlush(wrapOutboundOut(out), promise: nil)
        // Alternativa sem typealias: ctx.channel.writeAndFlush(out, promise: nil)
    }

    private func ts() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: Date())
    }
}

final class DiscoveryResponder: ChannelInboundHandler {
    typealias InboundIn  = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>  // <= Corrige erro 'Never'

    private let serverIP: String
    init(serverIP: String) { self.serverIP = serverIP }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let env = unwrapInboundIn(data)
        var buf = env.data
        guard let msg = buf.readString(length: buf.readableBytes) else { return }
        if msg == "DISCOVER_SERVER" {
            print("[\(Date())] Discovery de \(env.remoteAddress) → \(serverIP)")
            var out = context.channel.allocator.buffer(capacity: serverIP.utf8.count)
            out.writeString(serverIP)
            let reply = AddressedEnvelope(remoteAddress: env.remoteAddress, data: out)
            context.writeAndFlush(wrapOutboundOut(reply), promise: nil)
            // Alternativa: context.writeAndFlush(NIOAny(reply), promise: nil)
        }
    }
}

// -------- Bootstrap --------
func runServer() throws {
    let CHAT_PORT  = 1998
    let ADMIN_PORT = 2998
    let UDP_BCAST  = 30000
    let UDP_DISC   = 30001

    let start = Date()
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    let state = ServerState()
    let ip = firstNonLoopbackIPv4()

    print("""
    Servidor Online
    Ouvindo Chat: \(CHAT_PORT)
    Ouvindo API/Admin: \(ADMIN_PORT)
    IP do Servidor: \(ip)
    Listener UDP (discovery): \(UDP_DISC)
    Broadcast UDP: \(UDP_BCAST)
    Aguardando conexões...
    """)

    func makeServer(port: Int) throws -> Channel {
        try ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .childChannelInitializer { ch in
                ch.pipeline.addHandlers([
                    BackPressureHandler(),
                    ChatHandler(state: state, startTime: start)
                ])
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .bind(host: "0.0.0.0", port: port).wait()
    }

    // TCP listeners (chat e admin usam o mesmo handler)
    let chat  = try makeServer(port: CHAT_PORT)
    let admin = try makeServer(port: ADMIN_PORT)

    // UDP discovery (responde DISCOVER_SERVER na 30001)
    let udpResponder = try DatagramBootstrap(group: group)
        .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .channelInitializer { ch in ch.pipeline.addHandler(DiscoveryResponder(serverIP: ip)) }
        .bind(host: "0.0.0.0", port: UDP_DISC).wait()

    // UDP broadcast periódico do IP na 30000
    let udpBroadcaster = try DatagramBootstrap(group: group)
        .channelOption(ChannelOptions.socketOption(.so_broadcast), value: 1)
        .bind(host: "0.0.0.0", port: 0).wait()
    let bcastAddr = try SocketAddress(ipAddress: "255.255.255.255", port: UDP_BCAST)
    _ = udpBroadcaster.eventLoop.scheduleRepeatedTask(initialDelay: .seconds(0), delay: .seconds(10)) { _ in
        var buf = udpBroadcaster.allocator.buffer(capacity: ip.utf8.count)
        buf.writeString(ip)
        let env = AddressedEnvelope(remoteAddress: bcastAddr, data: buf)
        udpBroadcaster.writeAndFlush(env, promise: nil)
        print("[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] Broadcast UDP enviado: \(ip)")
    }

    try chat.closeFuture
        .and(admin.closeFuture)
        .and(udpResponder.closeFuture)
        .and(udpBroadcaster.closeFuture).wait()
    try group.syncShutdownGracefully()
}

// ---- Entry point top-level (sem @main) ----
do { try runServer() }
catch { fputs("FATAL: \(error)\n", stderr) }
