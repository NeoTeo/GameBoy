//
//  DmgMmu.swift
//  GameBoy
//
//  Created by Teo Sartori on 31/05/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

protocol MmuDelegate {
    func set(value: UInt8, on register: MmuRegister)
    
}

class DmgMmu : MMU {
    
    let size: Int// in bytes
    var ram: [UInt8]
    
    var delegate: MmuDelegate?
    
    enum MmuError : Error {
        case invalidAddress
    }
    
    // Constants
    //
    // The IE and IF registers are mapped to specific memory locations.
    let IEAddress = 0xFFFF
    let IFAddress = 0xFF0F
    
    let registerStartAddr: UInt16 = 0xFF00
    
    // Interrupt Enable.
    var IE: UInt8 {
        get { return ram[IEAddress] }
        set { ram[IEAddress] = newValue }
    }

    // Interrupt Flags. Set by hardware (eg. timer) when the relevant interrupts trigger.
    var IF: UInt8 {
        get { return ram[IFAddress] }
        set { ram[IFAddress] = newValue }
    }

    public enum RamError : Error {
        case Overflow
    }
    
    required init(size: Int) throws {
        guard size <= 0x10000 else { throw RamError.Overflow }
        self.size = size
        ram = Array(repeating: 0, count: Int(size))
        delegate = nil
    }
    
    // FIXME: For all r/w functions: Add some checks for writing to illegal
    // addresses and for remapping, etc.
    func read8(at location: UInt16) throws -> UInt8 {
        switch location {
        case 0xFF00 ... 0xFF7F: // We're in remapped country
            
            guard let mmuReg = MmuRegister(rawValue: UInt8(location & 0xFF)) else {
                print("MMU error: Unsupported register address.")
                throw MmuError.invalidAddress
            }
            
            switch mmuReg {
            case .ly: // Read only
                return ram[Int(location)]
            default:
                throw MmuError.invalidAddress
            }

        default:
            // deal with it as a direct memory access.
            return ram[Int(location)]
        }
//        
//        // If we get this far something's gone wrong.
//        throw MmuError.invalidAddress
    }

    func read16(at location: UInt16) -> UInt16 {
        let lsb = ram[Int(location)]
        let msb = ram[Int(location+1)]
        return (UInt16(msb) << 8) | UInt16(lsb)
    }
    
    func write(at location: UInt16, with value: UInt8) {
        
        switch location {
        case 0xFF00 ... 0xFF7F: // We're in remapped country
            
            guard let mmuReg = MmuRegister(rawValue: UInt8(location & 0xFF)) else {
                print("MMU error: Unsupported register address.")
                return
            }
            
            // FIXME: Perhaps better to figure out which subsystem (lcd, timer, etc)
            // the write is mapping to and pass the write on with a single call to
            // the appropriate delegate. Right now we have just the one delegate so...
            // But something like
            // switch location { case range of lcd: pass on to lcd case range of timer: pass to timer...
            switch mmuReg {
            case .lcdc:
                ram[Int(location)] = value
                delegate?.set(value: value, on: mmuReg)
            case .ly: break // Read only, ignore
            case .lyc:
                delegate?.set(value: value, on: mmuReg)
            case .scy: // vertical scroll
                ram[Int(location)] = value
                // let the LCD know we've updated the value
                delegate?.set(value: value, on: mmuReg)
            default:
                return
            }
            
        default:
            // deal with it as a direct memory access.
            ram[Int(location)] = value
        }
    }
}

// Called by the LCD.
extension DmgMmu : LcdDelegate {
    
    func set(value: UInt8, on register: MmuRegister) {
        // All LCD registers are defined as offsets relative to 0xFF00
        let location = registerStartAddr + UInt16(register.rawValue)
        ram[Int(location)] = value
    }
    
    func getValue(for register: MmuRegister) -> UInt8 {
        let location = registerStartAddr + UInt16(register.rawValue)
        return ram[Int(location)]
    }
}

// Helper functions
extension DmgMmu {

    func setIE(flag: mmuInterruptFlag) {
        IE = IE | UInt8(1 << flag.rawValue)
    }
    
    func setIF(flag: mmuInterruptFlag) {
        IF = IF | UInt8(1 << flag.rawValue)
    }
    
    func replace(data: [UInt8], from address: UInt16) throws {
        //ram.insert(contentsOf: data, at: Int(address))
        let start = Int(address)
        let end = start+data.count
        guard end < size else { throw RamError.Overflow }
        ram.replaceSubrange(start ..< end, with: data)
    }

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
