//
//  Student.swift
//  Manager
//
//  Created by Luccas Carneiro on 26/08/25.
//

import Foundation

internal class Student : Person {
    
    private var matricula: String
    private var curso: String
 
    init(_ matricula: String, _ curso: String) {
        super.init(nome: <#T##String#>, cpf: <#T##String#>, dataNascimento: <#T##Date#>)
        self.curso = curso
        self.matricula = matricula
    }
    
    internal func getMatricula() -> String {matricula}
    internal func getCurso() -> String {curso}
    
}
    
