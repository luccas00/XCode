//
//  main.swift
//  Manager
//
//  Created by Luccas Carneiro on 26/08/25.
//

import Foundation

internal class Functions {
        
    static let Instance = Functions()
    
    private init() {}
    
    func greet(person: String) -> String {
        let greeting = "Hello, " + person + "!"
        return greeting
    }

    func fatorial(_ number: Int) -> Int {
        
        if number <= 1 {
            return 1
        }
        
        return number * fatorial(number - 1)
        
    }
    
    func head() {
        
        print("- - - - - - - - - -")
        print("- - - - * * - - - -")
        print("- - - * * * * - - -")
        print("- - Hello There - -")
        print("- - - * * * * - - -")
        print("- - - - * * - - - -")
        print("- - - - - - - - - -")
        
    }
    
    func newDictionary() -> [Int: String] {
        
        var dictionary: [Int: String] = [:]
        dictionary = [1:"One", 2:"Two", 3:"Three", 4:"Four"]
        
        return dictionary
        
    }
    
    func newDictionary(_ size: Int) -> Dictionary<Int, String> {
        
        var dictionary: [Int: String] = [:]
        dictionary = [1:"One", 2:"Two", 3:"Three", 4:"Four", 5:"Five"]
        
        return dictionary
        
    }
    
    func newSet() -> Set<String> {
        return ["Neo", "Trinity", "Morpheus", "Neo", "Trinity", "Morpheus"]
    }
   
    func newDate( _ day: Int,  _ month: Int, _ year: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }
    
}
