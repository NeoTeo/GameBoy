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
    var bootRom: [UInt8]
    var cartridgeRom: [UInt8]?
    
    // Constants
    let romSize = 0x8000
    
    var romBank: UInt8 = 0
    
    var delegateLcd: MmuDelegate?
    var delegateTimer: MmuDelegate?
    
    enum MmuError : Error {
        case invalidAddress
        case noCartridgeRom
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
        set { ram[IFAddress] = 0xE0 | newValue } // The top 3 bits of IF are always set.
    }

    public enum RamError : Error {
        case Overflow
    }
    
    required init(size: Int) throws {
        guard size <= 0x10000 else { throw RamError.Overflow }
        self.size = size
        
        ram = Array(repeating: 0, count: Int(size))
        bootRom = Array(repeating: 0, count: Int(romSize))
        
        delegateLcd = nil
    }
    
    func mbcAddress(for location: UInt16, from bank: UInt8) -> UInt16 {
        
        // no need to convert addresses for bank 1
        guard bank > 1 else { return location }
        
        // 16K * number of banks + location offset.
        return 0x4000 * UInt16(bank-1) + location
    }
    // FIXME: For all r/w functions: Add some checks for writing to illegal
    // addresses and for remapping, etc.
    func read8(at location: UInt16) throws -> UInt8 {
        
        let romDisabled = isSet(bit: 0, in: ram[MmuRegister.romoff.rawValue])
        switch location {

        case 0x0000 ... 0x00FF where romDisabled == false:
                return bootRom[Int(location)]
            
        case 0x0000 ... 0x7FFF:
            guard let cart = cartridgeRom else { throw MmuError.noCartridgeRom }
            // Translate location based on selected ROM bank
            let address = (location >= 0x4000) ? mbcAddress(for: location, from: romBank) : location
            return cart[Int(address)]

        case 0x8000 ... 0x9FFF: // VRAM
            // If the LCD is in mode 3 (reading from both OAM and VRAM) we cannot read from VRAM
            guard (ram[MmuRegister.stat.rawValue] & 3) != 3 else {
                return 0xFF }
            return ram[Int(location)]
            
        case 0xFE00 ... 0xFE9F: // OAM RAM
            // If the LCD is in mode 2 (reading from both OAM) we cannot read from OAM
            guard (ram[MmuRegister.stat.rawValue] & 2) != 2 else { return 0xFF }
            return ram[Int(location)]
            
        case 0xFF00 ... 0xFF7F: // We're in remapped country
            
            if let mmuReg = MmuRegister(rawValue: Int(location)) {
                // FIXME: Do we even need to do this?
                // Only to deal with special cases that don't just return the byte at the location.
                switch mmuReg {
                case .ly, .lyc, .lcdc:
                    return ram[Int(location)]
                    
                case .scy, .scx: // scroll x and y
                    return ram[Int(location)]
                    
                case .wx, .wy: // window x and y position
                    return ram[Int(location)]
                    
                case .ir, .ie: // Interrupt request and interrupt enable
                    return ram[Int(location)]
                    
                case .p1: // Controller data at 0xFF00
                // FIXME: implement controller. For now return 0x00
                    return 0x00
                    
                default:
                    print("mmuReg is \(mmuReg)")
                    throw MmuError.invalidAddress
                }
            }
            
            print("MMU error: Unsupported register address: \(location & 0xFF).")
            print("Returning 0xFF")
            return 0xFF
//            return ram[Int(location)]

        default:
            // deal with it as a direct memory access.
            return ram[Int(location)]
        }
//        
//        // If we get this far something's gone wrong.
//        throw MmuError.invalidAddress
    }

    func read16(at location: UInt16) throws -> UInt16 {
//        let lsb = ram[Int(location)]
//        let msb = ram[Int(location+1)]
        let lsb = try read8(at: location)
        let msb = try read8(at: location+1)
        return (UInt16(msb) << 8) | UInt16(lsb)
    }
    
    func write(at location: UInt16, with value: UInt8) {

        switch location {
        case 0x2000 ... 0x3FFF: // ROM bank number (write only)
            romBank = value & 0x1F
            // A romBank of 0 is translated to bank 1
            if romBank == 0 { romBank = 1 }
            print("Switch to ROM bank \(romBank)")
            
        case 0xFF30 ... 0xFF3F: // Wave pattern ram
            // Just store
            ram[Int(location)] = value
            
        case 0x8000 ... 0x9FFF: // VRAM
            // If the LCD is in mode 3 (reading from both OAM and VRAM) we cannot write to VRAM
            guard (ram[MmuRegister.stat.rawValue] & 3) != 3 else {
                return }
            ram[Int(location)] = value
            
        case 0xFE00 ... 0xFE9F: // OAM RAM
            // If the LCD is in mode 2 (reading from both OAM) we cannot write to OAM
            guard (ram[MmuRegister.stat.rawValue] & 2) != 2 else { return }
            ram[Int(location)] = value

        case 0xFF00 ... 0xFF7F: // We're in remapped country
            
            guard let mmuReg = MmuRegister(rawValue: Int(location)) else {
                //print("MMU write error: Unsupported register address \(location & 0xFF). Ignoring.")
                return
            }
            
            // FIXME: Perhaps better to figure out which subsystem (lcd, timer, etc)
            // the write is mapping to and pass the write on with a single call to
            // the appropriate delegate. Right now we have just the one delegate so...
            // But something like
            // switch location { case range of lcd: pass on to lcd case range of timer: pass to timer...
            switch mmuReg {
                
            // Serial registers
            case .sc: // Serial control
                // currently there's no serial comms implemented but we do set the required interrupt
                ram[Int(location)] = value
//                if isSet(bit: 7, in: value) { setIF(flag: .serial) }
                if isSet(bit: 7, in: value) { set(bit: mmuInterruptBit.serial.rawValue, on: .ir) }
                
            // Timer registers
            case .div:
                delegateTimer?.set(value: value, on: mmuReg)
                break
            case .tima:
                delegateTimer?.set(value: value, on: mmuReg)
                break
            case .tma:
                delegateTimer?.set(value: value, on: mmuReg)
                break
            case .tac:
                delegateTimer?.set(value: value, on: mmuReg)
                break
                
            // LCD registers
            case .lcdc:
                ram[Int(location)] = value
                delegateLcd?.set(value: value, on: mmuReg)
            case .stat: // LCD status register
                ram[Int(location)] = value
                delegateLcd?.set(value: value, on: mmuReg)
                
            case .ly:
                break // Read only, ignore
            case .lyc:
                delegateLcd?.set(value: value, on: mmuReg)
                
            case .scy, .scx: // horizontal/vertical scroll
                ram[Int(location)] = value
                
                // let the LCD know we've updated the value
                delegateLcd?.set(value: value, on: mmuReg)

            case .wy, .wx: // horizontal/vertical window position
                ram[Int(location)] = value

            case .ir: // Interrupt request (IF)
                // The top three bits of IF are unused and always set.
                IF = value
            case .ie: // Interrupt enable (IE)
                IE = value
                
            case .romoff: // switch out rom
                print("switch out ROM")
                ram[Int(location)] = value
            default:
                return
            }
            
        default:
            // Do nothing if we're trying to write to rom
            if case (0x0000 ... 0x00FF) = location, isSet(bit: 0, in: ram[MmuRegister.romoff.rawValue]) == false {
                print("Attempting to write to ROM at location \(location). Ignoring.")
                return
            }
            // deal with it as a direct memory access.
            ram[Int(location)] = value
        }
    }
}

// Called by the LCD.
extension DmgMmu : LcdDelegate, TimerDelegate {
    
    func unsafeRead8(at location: UInt16) throws -> UInt8 {
        return ram[Int(location)]
    }
    
    func unsafeRead16(at location: UInt16) throws -> UInt16 {
        let loc = Int(location)
        let twobytes = Array(ram[loc ... loc+1])
        return UnsafePointer(twobytes).withMemoryRebound(to: UInt16.self, capacity: 1) { $0.pointee }
    }
    
    func set(bit: UInt8, on register: MmuRegister) {
        var regVal = ram[register.rawValue]
        regVal |= 1 << bit
        ram[register.rawValue] = regVal
    }
    
    func set(value: UInt8, on register: MmuRegister) {
        ram[register.rawValue] = value
    }
    
    func getValue(for register: MmuRegister) -> UInt8 {
        return ram[register.rawValue]
    }
}

// Helper functions
extension DmgMmu {
    
    
//    func setIE(flag: mmuInterruptFlag) {
//        IE = IE | UInt8(flag.rawValue)
//    }
//    
//    func setIF(flag: mmuInterruptFlag) {
//        IF = IF | UInt8(flag.rawValue)
//    }
    
    func replace(data: [UInt8], from address: UInt16) throws {
        //ram.insert(contentsOf: data, at: Int(address))
        let start = Int(address)
        let end = start+data.count
        guard end < size else { throw RamError.Overflow }
        ram.replaceSubrange(start ..< end, with: data)
    }

    func debugPrint(from: UInt16, bytes: UInt16, type: MemoryType = .mainRam) {
        let from = Int(from)
        let bytes = Int(bytes)
        guard from < size, (from + bytes <= size) else {
            print("debugPrint out of bounds error")
            return
        }
        
        var count = 0
        for index in from ..< from + bytes {
            
            if count == 0 { print(String(format: "%02X : ", index), terminator: " ") }
            
            switch type {
            case .mainRam: print(String(format: "%02X", ram[Int(index)]), terminator: " ")
            case .bootRom: print(String(format: "%02X", bootRom[Int(index)]), terminator: " ")
            case .cartRom: print(String(format: "%02X", (cartridgeRom?[Int(index)])!), terminator: " ")
            }
            
            
            count = (count + 1) % 0x10
            if count == 0 { print("") }
        }
        print("")
        print("---------")
    }
}
