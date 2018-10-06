//
//  Cartridge.swift
//  GameBoy
//
//  Created by Teo Sartori on 16/07/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

struct Cartridge {

    static public let CartSizes: [UInt8: Int] = [
        0x0 : 0x8000,   // 32 KByte
        0x1 : 0x10000,  // 64 KB
        0x2 : 0x20000,  // 128 KB
        0x3 : 0x40000,  // 256 KB
        0x4 : 0x80000,  // 512 KB
        0x5 : 0x100000, // 1 MB
        0x6 : 0x200000, // 2 MB
        0x7 : 0x400000, // 4 MB
        0x52 : 0x120000, // 1.1 MB
        0x53 : 0x140000, // 1.2 MB
        0x54 : 0x180000, // 1.5 MB
    ]

    var romSize: Int = 0
    
    var cartridgeRom: [UInt8]
    
    // 2 bit register to select a RAM bank range 0-3 OR to specify bits 5 and 6
    // of the ROM bank number if the romRamMode is set to ROM banking mode.
    var ramRomBank: UInt8 = 0
    
    // 1 bit register selects whether the ramRomBank number is used as a RAM bank number
    // or as extra bits to select a ROM bank.
    var romRamMode: UInt8 = 0
    
    // A 5 bit ROM bank number.
    var _romBank: UInt8 = 0
    public var romBank: UInt8 {
        set {
            
            // A romBank of 0 is translated to bank 1
            _romBank = newValue == 0 ? 1 : newValue
            
            if romRamMode == 0 {
                _romBank |= (ramRomBank << 5)
            }
            
//            if newValue == 8 { print("romBank request for bank \(newValue). Rombank now \(_romBank)") }
        }
        
        get { return _romBank }
    }
    
    var ramEnabled: Bool = false
    
    subscript(index: UInt16) -> UInt8 {
        
//        let bankedIndex = _romBank <= 1 ? Int(index) : 0x4000 * Int(_romBank - 1) + Int(index)
        var bankedIndex = 0
        if index < 0x4000 || _romBank <= 1 {
            bankedIndex = Int(index)
        } else {
            bankedIndex = 0x4000 * Int(_romBank - 1) + Int(index)
        }
        
//        guard bankedIndex < romSize else { throw CartridgeError.outOfBounds }
        // subscripts cannot throw so for now we just let it crash.
        
        return cartridgeRom[bankedIndex]
    }
}

/*
 func mbcAddress(for location: UInt16, from bank: UInt8) -> UInt16 {
 
 // no need to convert addresses for bank 1
 guard bank > 1 else { return location }
 
 // 16K * number of banks + location offset.
 return 0x4000 * UInt16(bank-1) + location
 }
 */
