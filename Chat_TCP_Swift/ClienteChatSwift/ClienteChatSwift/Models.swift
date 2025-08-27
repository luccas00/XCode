//
//  Models.swift
//  ClienteChatSwift
//
//  Created by Luccas Carneiro on 26/08/25.
//

import Foundation
import Network

struct UserEntry: Identifiable, Hashable {
    let id = UUID()
    let nick: String
    let ip: String
    let port: Int
}
