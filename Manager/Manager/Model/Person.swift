//
//  Pessoa.swift
//  Manager
//
//  Created by Luccas Carneiro on 26/08/25.
//

import Foundation

internal class Person {
    
    private var nome: String
    private var cpf: String
    private var dataNascimento: Date
    
    // Init padrão recebendo Date já pronto
    init(nome: String, cpf: String, dataNascimento: Date) {
        self.nome = nome
        self.cpf = cpf
        self.dataNascimento = dataNascimento
    }

    // Init utilizando o "newDate" (sua factory dentro de Functions)
    convenience init(nome: String, cpf: String, dia: Int, mes: Int, ano: Int) {
        let dt = Functions.Instance.newDate(dia, mes, ano)
        self.init(nome: nome, cpf: cpf, dataNascimento: dt)
    }

    internal func idade() -> Int {
        let hoje = Date()
        let calendar = Calendar.current
        return calendar.dateComponents([.year], from: dataNascimento, to: hoje).year ?? 0
    }
    
    // Data de nascimento formatada
    internal func dataNascimentoFormatada() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: dataNascimento)
    }
    
}
