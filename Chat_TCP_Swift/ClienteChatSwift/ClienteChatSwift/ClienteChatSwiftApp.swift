//
//  ClienteChatSwiftApp.swift
//  ClienteChatSwift
//
//  Created by Luccas Carneiro on 26/08/25.
//

import SwiftUI

@main
struct ClienteChatSwiftApp: App {
    @StateObject private var vm = ChatViewModel()

    var body: some Scene {
        // Janela principal
        WindowGroup {
            ContentView()
                .environmentObject(vm)
        }
        // Janela(s) de chat privado, uma por sessão (key = UUID da sessão)
        WindowGroup("Chat Privado", for: UUID.self) { $sessionID in
            if let id = sessionID, let session = vm.privateSessions[id] {
                PrivateChatView(session: session)
            } else {
                Text("Conectando…").frame(minWidth: 420, minHeight: 320)
            }
        }
        .environmentObject(vm)
    }
}

