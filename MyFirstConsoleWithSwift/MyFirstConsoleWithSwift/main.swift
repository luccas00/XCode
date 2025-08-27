//
//  main.swift
//  MyFirstConsoleWithSwift
//
//  Created by Luccas Carneiro on 26/08/25.
//

import Foundation

print("Hello, World!")

let pi = 3.14159
let π = 3.14159
let Ω = 10
let text = "Apple"
let ß = 7.77

var green, blue, red: Double
var flag, toggle: Bool
var index, count: Int

var lista: [String]

var set: Set<String>

var dictionary: [Int: String] = [:]

print("Pi: \(pi)")
print("π: \(π)")
print("Ω: \(Ω)")
print("ß: \(ß)")
print("text: \(text) ")

green = 3
blue = 4
red = 5

flag = true
toggle = false

lista = ["Eggs", "Milk", "Sugar"]
set = ["Neo", "Trinity", "Morpheus", "Neo", "Trinity", "Morpheus"]
dictionary = [1:"One", 2:"Two", 3:"Three", 4:"Four"]

print(green, blue, red)

print(flag, toggle)

for text in lista {
    print(text)
}

for item in set {
    print(item)
}

for item in dictionary {
    print(item)
}

lista.append("Meat")

set.insert("Neo")
set.insert("Seraph")

var nextKey = dictionary.count + 1
dictionary[nextKey] = "Five"

for text in lista {
    print(text)
}

for item in set {
    print(item)
}

for item in dictionary {
    print(item)
}

for (key, value) in dictionary {
    
    print("Numero: \(key) - Escrita: \(value)")
    
}

print("- - - - -")

for (key, value) in dictionary.sorted(by: { $0.key < $1.key }) {
    
    print("Numero: \(key) - Escrita: \(value)")
    
}

var i = 0
while i < 3 {
    
    i += 1
    print(i)
    
}


