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

func ts() -> String {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: Date())
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
    func remove(channel: Channel) -> ClientInfo? {
        lock.withLock {
            let id = ObjectIdentifier(channel)
            if let info = byChannel.removeValue(forKey: id) {
                byNick.removeValue(forKey: info.apelido.lowercased())
                return info
            }
            return nil
        }
    }
    func count() -> Int { lock.withLock { byChannel.count } }
    func listCSV() -> String {
        lock.withLock {
            byChannel.values
                .map { "\($0.apelido);\($0.ip);\($0.portaPrivada)" }
                .sorted() // ordena para estabilidade visual
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
    func nicknames() -> [String] {
        lock.withLock { byChannel.values.map(\.apelido).sorted() }
    }
}

// -------- Handlers ----------
final class ChatHandler: ChannelInboundHandler {
    typealias InboundIn   = ByteBuffer
    typealias OutboundOut = ByteBuffer

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
        let removed = state.remove(channel: context.channel)
        if let info = removed {
            let msg = "[\(ts())] [server] \(info.apelido) saiu. Online: \(state.count())"
            print("LEAVE  -> \(msg)")
            broadcast(msg, excluding: nil)
        } else {
            print("DESC   -> canal removido, apelido desconhecido. Online: \(state.count())")
        }
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

                    // Boas-vindas ao novo cliente
                    write(context, "[\(ts())] [server] Bem-vindo, \(apelido)! Usuários online: \(state.count())")

                    // Aviso a todos
                    let joinMsg = "[\(ts())] [server] \(apelido) entrou (\(ipRemoto):\(portaPrivada)). Online: \(state.count())"
                    print("JOIN   -> \(joinMsg)")
                    broadcast(joinMsg, excluding: nil)
                }
            }
            return
        }

        handleMessage(context: context, raw: chunk)
    }

    private func handleMessage(context: ChannelHandlerContext, raw: String) {
        let mensagem = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch true {
        case mensagem == "/count":
            let resp = "Usuarios Conectados: \(state.count())"
            print("CMD    -> /count => \(resp)")
            write(context, resp)

        case mensagem == "/lista":
            print("CMD    -> /lista")
            write(context, state.listCSV())

        case mensagem.hasPrefix("/desconectar "):
            let nick = String(mensagem.dropFirst("/desconectar".count)).trimmingCharacters(in: .whitespaces)
            print("CMD    -> /desconectar \(nick)")
            if let ch = state.findChannel(nick: nick) {
                ch.close(promise: nil)
                write(context, "Usuário \(nick) desconectado com sucesso.")
                let msg = "[\(ts())] [server] \(nick) foi desconectado via comando."
                broadcast(msg, excluding: nil)
            } else {
                write(context, "Usuário \(nick) não encontrado.")
            }

        case mensagem == "/status":
            let up = Int(Date().timeIntervalSince(startTime))
            let resp = "Servidor online - Usuários conectados: \(state.count()) - Uptime: \(up)s"
            print("CMD    -> /status => \(resp)")
            write(context, resp)

        case mensagem == "/help":
            let resp = """
            Comandos: /count, /lista, /status, /desconectar <apelido>
            """
            print("CMD    -> /help")
            write(context, resp)

        default:
            // Broadcast de chat SEMPRE com apelido + timestamp
            let final = "[\(ts())] \(apelido): \(mensagem)"
            print("BCAST  -> \(final)")
            broadcast(final, excluding: nil)
        }
    }

    // Broadcast helper (opção de excluir quem enviou, se necessário)
    private func broadcast(_ text: String, excluding excluded: Channel?) {
        for c in state.all() {
            if let ex = excluded, ex === c.channel { continue }
            var out = c.channel.allocator.buffer(capacity: text.utf8.count)
            out.writeString(text)
            _ = c.channel.writeAndFlush(out)
        }
    }

    private func write(_ ctx: ChannelHandlerContext, _ text: String) {
        var out = ctx.channel.allocator.buffer(capacity: text.utf8.count)
        out.writeString(text)
        ctx.writeAndFlush(wrapOutboundOut(out), promise: nil)
    }
}

final class DiscoveryResponder: ChannelInboundHandler {
    typealias InboundIn   = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    private let serverIP: String
    init(serverIP: String) { self.serverIP = serverIP }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let env = unwrapInboundIn(data)
        var buf = env.data
        guard let msg = buf.readString(length: buf.readableBytes) else { return }
        if msg == "DISCOVER_SERVER" {
            // Mantém resposta apenas com IP (compatibilidade legado)
            var out = context.channel.allocator.buffer(capacity: serverIP.utf8.count)
            out.writeString(serverIP)
            let reply = AddressedEnvelope(remoteAddress: env.remoteAddress, data: out)
            print("UDP-RX -> \(Date()) from \(env.remoteAddress) payload: \(msg) | reply: \(serverIP)")
            context.writeAndFlush(wrapOutboundOut(reply), promise: nil)
        } else {
            print("UDP-RX -> ignorado payload: \(msg)")
        }
    }
}

// -------- Bootstrap --------
func runServer() throws {
    // Config “via env” (fallback para defaults)
    let CHAT_PORT  = Int(ProcessInfo.processInfo.environment["CHAT_PORT"]  ?? "1998") ?? 1998
    let ADMIN_PORT = Int(ProcessInfo.processInfo.environment["ADMIN_PORT"] ?? "2998") ?? 2998
    let UDP_BCAST  = Int(ProcessInfo.processInfo.environment["UDP_BCAST"]  ?? "30000") ?? 30000
    let UDP_DISC   = Int(ProcessInfo.processInfo.environment["UDP_DISC"]   ?? "30001") ?? 30001
    let BCAST_EVERY_SECONDS: Int64 = Int64(ProcessInfo.processInfo.environment["BCAST_EVERY"] ?? "10") ?? 10

    let start = Date()
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    let state = ServerState()
    let ip = firstNonLoopbackIPv4()

    print("""
    ====== Servidor Online (\(ts())) ======
    Ouvindo Chat (TCP): \(CHAT_PORT)
    Ouvindo Admin (TCP): \(ADMIN_PORT)
    IP do Servidor: \(ip)
    UDP Discovery (RX): \(UDP_DISC)
    UDP Broadcast (TX): \(UDP_BCAST) a cada \(BCAST_EVERY_SECONDS)s
    =======================================
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

    // UDP broadcast periódico do IP na 30000 (payload = IP puro)
    let udpBroadcaster = try DatagramBootstrap(group: group)
        .channelOption(ChannelOptions.socketOption(.so_broadcast), value: 1)
        .bind(host: "0.0.0.0", port: 0).wait()
    let bcastAddr = try SocketAddress(ipAddress: "255.255.255.255", port: UDP_BCAST)

    _ = udpBroadcaster.eventLoop.scheduleRepeatedTask(initialDelay: .seconds(0), delay: .seconds(BCAST_EVERY_SECONDS)) { _ in
        var buf = udpBroadcaster.allocator.buffer(capacity: ip.utf8.count)
        buf.writeString(ip)
        let env = AddressedEnvelope(remoteAddress: bcastAddr, data: buf)
        udpBroadcaster.writeAndFlush(env, promise: nil)

        // Log do broadcast + visão de conectados (com apelidos)
        let nicks = state.nicknames().joined(separator: ", ")
        print("UDP-TX -> \(ts()) broadcast: \(ip) | online=\(state.count()) | nicks=[\(nicks)]")
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
