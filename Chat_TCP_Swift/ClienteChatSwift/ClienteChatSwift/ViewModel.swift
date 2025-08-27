//
//  ViewModel.swift
//  ClienteChatSwift
//
//  Created by Luccas Carneiro on 26/08/25.
//

import Foundation
import Combine

final class ChatViewModel: ObservableObject {
    
    // Inputs
    @Published var nickname: String = ""
    @Published var serverIp: String = ""
    @Published var serverPort: Int = 1998
    @Published var outbound: String = ""

    // Identidade local
    @Published var myLocalIP: String = firstNonLoopbackIPv4()   // <-- NOVO
    @Published var myPrivatePort: UInt16 = 0                    // <-- NOVO

    // State
    @Published var connected: Bool = false
    @Published var messages: [String] = []
    @Published var users: [UserEntry] = []
    @Published var lastOpenedSessionID: UUID?

    // Infra
    private let udp = UdpDiscovery()
    private let client = ChatClient()
    private let listener = PrivateListener()

    // P2P
    @Published var privateSessions: [UUID: PrivateChatSession] = [:]
    init() {
        // Broadcast discovery -> autopreenche IP
        udp.startListening { [weak self] ip in
            guard let self, !self.connected else { return }
            self.serverIp = ip
        }

        client.onMessage = { [weak self] s in self?.append(s) }
        client.onUserList = { [weak self] list in self?.users = list }

        try? listener.start()
        // Atualiza porta privada local publicada
        listener.onReady = { [weak self] port in self?.myPrivatePort = port }    // <-- NOVO

        // Conexões entrantes -> abrir janela com metadados locais
        listener.onIncoming = { [weak self] session in
            guard let self else { return }
            session.hydrateLocal(nick: self.nickname, ip: self.myLocalIP, port: self.myPrivatePort)
            self.registerPrivate(session: session, title: "Privado (entrada)")
        }

    }
    
    init(preview: Bool = false) {
        if preview {
            // MOCK para o Preview (não abre sockets)
            self.nickname = "Luccas"
            self.serverIp = "192.168.0.10"
            self.serverPort = 1998
            self.connected = true
            self.messages = [
                "Servidor: Bem-vindo",
                "Neo: Olá",
                "Você: Testando preview"
            ]
            self.users = [
                UserEntry(nick: "Neo", ip: "192.168.0.20", port: 50001),
                UserEntry(nick: "Trinity", ip: "192.168.0.21", port: 50002)
            ]
            return
        }

        // PRODUÇÃO (abre sockets normalmente)
        udp.startListening { [weak self] ip in
            guard let self, !self.connected else { return }
            self.serverIp = ip
        }
        client.onMessage = { [weak self] s in self?.messages.append(s) }
        client.onUserList = { [weak self] list in self?.users = list }

        try? listener.start()
        listener.onIncoming = { [weak self] session in
            guard let self else { return }
            self.privateSessions[session.id] = session
            self.lastOpenedSessionID = session.id
        }
    }

        

    func discover() {
        udp.discover { [weak self] ip in
            DispatchQueue.main.async {
                if let ip { self?.serverIp = ip }
            }
        }
    }

    func connect() {
        guard !nickname.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let ip = serverIp.trimmingCharacters(in: .whitespaces)
        guard let port = UInt16(exactly: serverPort) else { return }

        client.connect(ip: ip,
                       port: port,
                       nickname: nickname,
                       privatePort: myPrivatePort) { [weak self] in
            DispatchQueue.main.async { self?.connected = true }
        } onError: { [weak self] err in
            self?.append("[erro] \(err)")
        }
    }

    func openPrivateChat(to user: UserEntry) {
        // Sessão ativa com todos os metadados
        let session = PrivateChatSession(host: user.ip,
                                         port: UInt16(user.port),
                                         localNickname: nickname,
                                         localIP: myLocalIP,
                                         localPort: myPrivatePort,
                                         remoteNick: user.nick)
        session.start()
        registerPrivate(session: session)
    }

    func registerPrivate(session: PrivateChatSession) {
        privateSessions[session.id] = session
        DispatchQueue.main.async { self.lastOpenedSessionID = session.id }
    }


    func disconnect() {
        client.disconnect()
        connected = false
        users.removeAll()
        messages.removeAll()
        outbound = ""
    }

    func requestList() { client.send("/lista") }
    func requestCount() { client.send("/count") }
    func requestStatus() { client.send("/status") }

    func sendBroadcast() {
        guard !outbound.isEmpty else { return }
        client.send(outbound)
        append("Você: \(outbound)")
        outbound = ""
    }

    // registerPrivate(...): atualize para guardar a última sessão
    func registerPrivate(session: PrivateChatSession, title: String) {
        privateSessions[session.id] = session
        DispatchQueue.main.async { self.lastOpenedSessionID = session.id } // <— dispara janela
    }


    private func append(_ s: String) {
        messages.append(s)
    }
}
