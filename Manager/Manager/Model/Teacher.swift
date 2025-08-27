//
//  Teacher.swift
//  Manager
//
//  Created by Luccas Carneiro on 26/08/25.
//


internal class Teacher : Person {
    
    private var salario: Double
    private var departamento: String
 
    init(_ matricula: String, _ curso: String) {
        super.init(nome: <#T##String#>, cpf: <#T##String#>, dataNascimento: <#T##Date#>)
        self.curso = curso
        self.matricula = matricula
    }
    
    internal func getMatricula() -> String {matricula}
    internal func getCurso() -> String {curso}
    
}
