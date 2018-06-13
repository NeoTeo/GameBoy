//
//  ram.swift
//  GameBoy
//
//  Created by Teo Sartori on 31/05/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

class RAM : MEMORY {
    
    let size: Int// in bytes
    var ram: [UInt8]
    
    public enum RamError : Error {
        case Overflow
    }
    
    required init(size: Int) throws {
        guard size <= 0x10000 else { throw RamError.Overflow }
        self.size = size
        ram = Array(repeating: 0, count: Int(size))
    }
    
    func read16(at location: UInt16) -> UInt16 {
        let lsb = ram[Int(location)]
        let msb = ram[Int(location+1)]
        return (UInt16(msb) << 8) | UInt16(lsb)
    }
    
    func read8(at location: UInt16) -> UInt8 {
        return ram[Int(location)]
    }
    
    // FIXME: Add some checks for writing to illegal addresses.
    func write(at location: UInt16, with value: UInt8) {
        ram[Int(location)] = value
    }
    
    // Helper functions
    func replace(data: [UInt8], from address: UInt16) throws {
        //ram.insert(contentsOf: data, at: Int(address))
        let start = Int(address)
        let end = start+data.count
        guard end < size else { throw RamError.Overflow }
        ram.replaceSubrange(start ..< end, with: data)
    }
}

// Helper functions
extension RAM {
    
    func debugPrint(from: UInt16, bytes: UInt16) {
        let from = Int(from)
        let bytes = Int(bytes)
        guard from < size, (from + bytes <= size) else {
            print("debugPrint out of bounds error")
            return
        }
        
        var count = 0
        for index in from ..< from + bytes {
            
            if count == 0 { print(String(format: "%02X : ", index), terminator: " ") }
            
            print(String(format: "%02X", ram[Int(index)]), terminator: " ")
            
            count = (count + 1) % 0x10
            if count == 0 { print("") }
        }
        print("")
        print("---------")
    }
}
