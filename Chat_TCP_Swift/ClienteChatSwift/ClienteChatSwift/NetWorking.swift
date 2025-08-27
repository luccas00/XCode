//
//  NetWorking.swift
//  ClienteChatSwift
//
//  Created by Luccas Carneiro on 26/08/25.
//

import Foundation
import Network

// MARK: - UDP Discovery (30000 listener / 30001 discover)
final class UdpDiscovery {
    private var recvSocket: Int32 = -1
    private let queue = DispatchQueue(label: "udp.discovery.queue")

    // Listener UDP 30000 para receber broadcasts de IP do servidor
    func startListening(updateIp: @escaping (String) -> Void) {
        queue.async {
            self.recvSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard self.recvSocket >= 0 else { return }
            var yes: Int32 = 1
            setsockopt(self.recvSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(30000).bigEndian
            addr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = bind(self.recvSocket, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            var buf = [UInt8](repeating: 0, count: 1024)
            while true {
                let n = recv(self.recvSocket, &buf, buf.count, 0)
                if n > 0 {
                    let ip = String(decoding: buf[0..<n], as: UTF8.self)
                    DispatchQueue.main.async { updateIp(ip.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
            }
        }
    }

    // Envia "DISCOVER_SERVER" para 255.255.255.255:30001 e aguarda resposta (IP do servidor)
    func discover(timeout: TimeInterval = 3.0, completion: @escaping (String?) -> Void) {
        DispatchQueue.global().async {
            let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard sock >= 0 else { completion(nil); return }
            defer { close(sock) }

            var yes: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
            setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))

            var dest = sockaddr_in()
            dest.sin_family = sa_family_t(AF_INET)
            dest.sin_port = in_port_t(30001).bigEndian
            dest.sin_addr.s_addr = inet_addr("255.255.255.255")

            let payload = "DISCOVER_SERVER"
            let bytes = [UInt8](payload.utf8)

            let sent = withUnsafePointer(to: &dest) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(sock, bytes, bytes.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard sent >= 0 else { completion(nil); return }

            // timeout de leitura
            var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
            setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            var buf = [UInt8](repeating: 0, count: 1024)
            var from = sockaddr_in()
            var len: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(sock, &buf, buf.count, 0, sa, &len)
                }
            }
            if n > 0 {
                let ip = String(decoding: buf[0..<n], as: UTF8.self)
                completion(ip.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                completion(nil)
            }
        }
    }
}

// MARK: - Listener P2P (porta privada dinâmica)
final class PrivateListener {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "private.listener.queue")
    var localPort: UInt16 = 0
    var onIncoming: ((PrivateChatSession) -> Void)?

    func start() throws {
        let params = NWParameters.tcp
        let l = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: 0))
        self.listener = l

        l.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            let session = PrivateChatSession(existing: conn)
            self.onIncoming?(session)
            session.start()
        }

        l.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let port = l.port {
                self?.localPort = port.rawValue
            }
        }

        l.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}

// MARK: - Sessão P2P
final class PrivateChatSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published var messages: [String] = []
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "private.chat.session")
    private let localNickname: String?

    // Conectar ativo
    init(host: String, port: UInt16, localNickname: String? = nil) {
        self.localNickname = localNickname
        let endpoint = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        connection = NWConnection(host: endpoint, port: nwPort, using: .tcp)
    }
    // Conexão recebida
    init(existing: NWConnection) {
        connection = existing
        self.localNickname = nil
    }

    func start() {
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let name = self?.localNickname {
                    self?.connection?.send(content: Data(name.utf8), completion: .contentProcessed({ _ in }))
                }
                self?.receiveLoop()
            default: break
            }
        }
        connection?.start(queue: queue)
    }

    func send(_ text: String) {
        guard let conn = connection else { return }
        let data = Data(text.utf8)
        conn.send(content: data, completion: .contentProcessed({ _ in }))
        append("Você: \(text)")
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            if let d = data, !d.isEmpty, let s = String(data: d, encoding: .utf8) {
                self?.append(s)
            }
            if error == nil && !isComplete {
                self?.receiveLoop()
            }
        }
    }

    private func append(_ s: String) {
        DispatchQueue.main.async { self.messages.append(s) }
    }

    func close() { connection?.cancel() }
}

// MARK: - Chat Client (TCP 1998)
final class ChatClient {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "chat.client.queue")

    var onMessage: ((String) -> Void)?
    var onUserList: (([UserEntry]) -> Void)?

    func connect(ip: String, port: UInt16, nickname: String, privatePort: UInt16, onReady: @escaping () -> Void, onError: @escaping (String) -> Void) {
        let host = NWEndpoint.Host(ip)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let conn = NWConnection(host: host, port: nwPort, using: .tcp)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Handshake: "apelido;portaPrivada" (sem newline)
                let hs = "\(nickname);\(privatePort)"
                conn.send(content: Data(hs.utf8), completion: .contentProcessed({ _ in onReady() }))
                self?.receiveLoop()
            case .failed(let err):
                onError(err.localizedDescription)
            default: break
            }
        }
        conn.start(queue: queue)
    }

    func send(_ text: String) {
        guard let c = connection else { return }
        c.send(content: Data(text.utf8), completion: .contentProcessed({ _ in }))
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            if let d = data, !d.isEmpty, let s = String(data: d, encoding: .utf8) {
                self?.processInbound(s)
            }
            if error == nil && !isComplete {
                self?.receiveLoop()
            }
        }
    }

    private func processInbound(_ s: String) {
        // Heurística igual ao cliente C#: conteúdo com ';' e '\n' => lista de usuários
        if s.contains(";"), s.contains("\n") {
            let lines = s.split(whereSeparator: { $0.isNewline })
            let list: [UserEntry] = lines.compactMap { line in
                let cols = line.split(separator: ";").map(String.init)
                guard cols.count == 3, let p = UInt16(cols[2]) else { return nil }
                return UserEntry(nick: cols[0], ip: cols[1], port: Int(p))
            }
            DispatchQueue.main.async { self.onUserList?(list) }
        } else {
            DispatchQueue.main.async { self.onMessage?(s) }
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }
}
