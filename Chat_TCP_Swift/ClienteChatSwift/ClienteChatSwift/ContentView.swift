//
//  ContentView.swift
//  ClienteChatSwift
//
//  Created by Luccas Carneiro on 26/08/25.
//

import SwiftUI

struct ContentView: View {
    
    @EnvironmentObject var vm: ChatViewModel
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(spacing: 12) {
            header
            actionBar
            HStack(spacing: 12) { messagesPane; usersPane }
            broadcaster
        }
        .padding(12)
        .frame(minWidth: 900, minHeight: 520)
        // Quando o ViewModel registra uma nova sessão, abre a janela correspondente
        .onChange(of: vm.lastOpenedSessionID) { _, newID in
            if let id = newID { openWindow(value: id) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            TextField("Apelido", text: $vm.nickname)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            TextField("IP do Servidor", text: $vm.serverIp)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            TextField("Porta (1–65535)", value: $vm.serverPort, formatter: Self.portFormatter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                .onChange(of: vm.serverPort) { newValue in
                    // hard clamp defensivo
                    vm.serverPort = min(max(newValue, 1), 65535)
                }

            Spacer()

            Button("Descobrir (UDP)") { vm.discover() }
            Button(vm.connected ? "Desconectar" : "Conectar") {
                vm.connected ? vm.disconnect() : vm.connect()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(vm.nickname.isEmpty || vm.serverIp.isEmpty)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button("Listar Usuários") { vm.requestList() }.disabled(!vm.connected)
            Button("Count") { vm.requestCount() }.disabled(!vm.connected)
            Button("Status") { vm.requestStatus() }.disabled(!vm.connected)
            Spacer()
            Text(vm.connected ? "Conectado" : "Offline")
                .foregroundStyle(vm.connected ? .green : .red)
        }
    }

    private var messagesPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mensagens")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(Array(vm.messages.enumerated()), id: \.offset) { _, msg in
                        Text(msg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.vertical, 2)
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(minWidth: 560)
    }

    private var usersPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usuários").font(.headline)
            List(vm.users) { u in
                HStack {
                    VStack(alignment: .leading) {
                        Text(u.nick).fontWeight(.semibold)
                        Text("\(u.ip):\(u.port)").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Privado") {
                        vm.openPrivateChat(to: u) // só isso. A janela abrirá via onChange acima.
                    }
                }
            }
            .frame(minWidth: 260, maxHeight: .infinity)
        }
        .frame(minWidth: 300)
    }

    private var broadcaster: some View {
        HStack(spacing: 8) {
            TextField("Mensagem broadcast…", text: $vm.outbound)
                .textFieldStyle(.roundedBorder)
                .disabled(!vm.connected)
            Button("Enviar") { vm.sendBroadcast() }
                .disabled(!vm.connected || vm.outbound.isEmpty)
        }
    }
    
    private static let portFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.allowsFloats = false
        f.minimum = 1
        f.maximum = 65535
        return f
    }()

    
}

struct PrivateChatView: View {
    @ObservedObject var session: PrivateChatSession
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(Array(session.messages.enumerated()), id: \.offset) { _, msg in
                        Text(msg).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            HStack {
                TextField("Mensagem privada…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button("Enviar") {
                    guard !draft.isEmpty else { return }
                    session.send(draft)
                    draft = ""
                }
            }
        }
        .padding(12)
        .frame(minWidth: 520, minHeight: 360)
    }
}

// --- IP local (IPv4 não-loopback) ---
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

// --- Modifier para setar o título da janela (macOS) ---
import AppKit

struct WindowTitleModifier: ViewModifier {
    let title: String
    func body(content: Content) -> some View {
        content.background(WindowTitleSetter(title: title))
    }
    private struct WindowTitleSetter: NSViewRepresentable {
        let title: String
        func makeNSView(context: Context) -> NSView {
            let v = NSView()
            DispatchQueue.main.async { v.window?.title = title }
            return v
        }
        func updateNSView(_ nsView: NSView, context: Context) {
            DispatchQueue.main.async { nsView.window?.title = title }
        }
    }
}
extension View {
    func windowTitle(_ title: String) -> some View { modifier(WindowTitleModifier(title: title)) }
}



//#Preview {
//    ContentView()
//        .environmentObject(ChatViewModel(preview: true))
//}
