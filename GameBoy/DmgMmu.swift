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
//    var cartridgeRom: [UInt8]?
    var cartridgeRom: Cartridge?
    
    // Constants
    let romSize = 0x8000
    /*
    // 2 bit register to select a RAM bank range 0-3 OR to specify bits 5 and 6
    // of the ROM bank number if the romRamMode is set to ROM banking mode.
    var ramRomBank: UInt8 = 0
    
    // 1 bit register selects whether the ramRomBank number is used as a RAM bank number
    // or as extra bits to select a ROM bank.
    var romRamMode: UInt8 = 0
    
    // A 5 bit ROM bank number.
    var romBank: UInt8 = 0
    
    var cartRamEnabled: Bool = false
    */
    var delegateLcd: MmuDelegate?
    var delegateTimer: MmuDelegate?
    var delegateController: MmuDelegate?
    
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
    
    // Cartridge ROM data is used init a Cartridge from its header.
    func connectCartridge(rom: [UInt8]) {
        
        // TODO: turn into throw
        guard rom.count >= 0x8000 else {
            print("ROM too small.")
            return
        }
        // Read cartridge type:
        let cartType = rom[0x147]
        print("Cartridge type: \(cartType)")
        // Read cartridge ROM size
        let cartRomSize = Cartridge.CartSizes[rom[0x148]] ?? 0 //rom[0x148]
        print("Cartridge ROM size: \(cartRomSize)")
        // read cartridge RAM size
        let cartRamSize = rom[0x149]
        print("Cartridge RAM size: \(cartRamSize)")
        
//        cartridgeRom = rom
//        cartridgeRom = Cartridge(romSize: cartRomSize,
//                                 cartridgeRom: rom,
//                                 ramRomBank: 0,
//                                 romRamMode: 0,
//                                 romBank: 0,
//                                 ramEnabled: false
//        )
        cartridgeRom = Cartridge(romSize: cartRomSize, cartridgeRom: rom, ramRomBank: 0, romRamMode: 0, _romBank: 0, ramEnabled: false)
//        cartridgeRom?.romSize = Cartridge.CartSizes[rom[0x148]] ?? 0
//        cartridgeRom?.ramRomBank = 0
//        cartridgeRom?.romRamMode = 0
        
    }
    
//    func mbcAddress(for location: UInt16, from bank: UInt8) -> UInt16 {
//        
//        // no need to convert addresses for bank 1
//        guard bank > 1 else { return location }
//        
//        // 16K * number of banks + location offset.
//        return 0x4000 * UInt16(bank-1) + location
//    }
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
//            let address = (location >= 0x4000) ? mbcAddress(for: location, from: romBank) : location
//            return cart[Int(address)]
            return cart[location]
            
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
                    
                case .sb, .sc: // Serial data transfer
                    // Not implemented serial comms so for now just return 0xFF
                    return 0xFF
//                    return ram[Int(location)]
                    
                case .p1: // controller
                    // When reading, the values significance will depend on bits 4 and 5.
                    // for bits 4 and 5, 0=select
                    // for bits 0 to 3, 0=pressed
                    // If bit 4 is 0 then the bits 0 to 3 will refer to the directional pad
                    // and if bit 5 is 0 then bits 0 to 3 will refer to the A, B, Select and Start.
                    return ram[Int(location)]
                 
                case .div:
                    // Perhaps this should go through the timerDelegate...?
                    return ram[Int(location)]
                    
                case .ly, .lyc, .lcdc, .stat:
                    return ram[Int(location)]
                    
                case .bgp, .obp0, .obp1: // Palette data (BG, OBP0, OBP1)
                    return ram[Int(location)]
                    
                case .scy, .scx: // scroll x and y
                    return ram[Int(location)]
                    
                case .wx, .wy: // window x and y position
                    return ram[Int(location)]
                    
                case .ir, .ie: // Interrupt request and interrupt enable
                    return ram[Int(location)]
                                        
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
    
    // TODO: factor cartridge specific code out into own class/struct.
    func write(at location: UInt16, with value: UInt8) {

        switch location {
            
        case 0x0000 ... 0x1FFF: // Cartridge RAM enable.
            // Cartridge RAM enabled
            cartridgeRom?.ramEnabled = (value & 0xA) == 0xA
            
        case 0x2000 ... 0x3FFF: // ROM bank number (write only)
            
            // Uses only lower 5 bits (0 to 4)
            cartridgeRom?.romBank = value & 0x1F
//            print("Switch to ROM bank \(cartridgeRom?.romBank)")
            
        case 0x4000 ... 0x5FFF: // RAM bank number or ROM bank number (upper bits, 5 and 6),
            // which depends on ROMRAM mode.
            cartridgeRom?.ramRomBank = value & 0x3
            
        case 0x6000 ... 0x7FFF: // ROMRAM mode select.
            cartridgeRom?.romRamMode = value & 0x1
            
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
                
            case .p1:   // Controller data
                // We can only write to bits 4 and 5.
                // If bit 4 is 0 the direction keys are selected
                // If bit 5 is 0, the button keys are selected
                // This means, when reading this register, the values in bits 0 to 3 will refer to
                // the selected keys.
                let ramVal = ram[Int(location)]
                // Ensure only bits 4 and 5 are used.
                let val = value & 0x30
                // Mask out (&) bits 4 and 5 and | in the new value.
                ram[Int(location)] = (ramVal & 0xCF) | val
                
                delegateController?.set(value: val, on: .p1)
                
            // Serial registers
            case .sb: // Serial transfer data
                // not implemented. Ignore
                break
                
            case .sc: // Serial control
                // currently there's no serial comms implemented
//                ram[Int(location)] = value

                // We would set the required interrupt once the transfer was completed.
//                if isSet(bit: 7, in: value) { set(bit: mmuInterruptBit.serial.rawValue, on: .ir) }
                
                // Pretending we've initiated the transfer we now reset the SC7 bit
//                ram[Int(location)] = clear(bit: 7, in: value)
                break
                
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

            case .bgp, .obp0, .obp1: // Palette data (BG, OBP0, OBP1)
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
extension DmgMmu : LcdDelegate, TimerDelegate, ControllerDelegate {
    
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
            case .cartRom: print(String(format: "%02X", (cartridgeRom?[UInt16(index)])!), terminator: " ")
            }
            
            
            count = (count + 1) % 0x10
            if count == 0 { print("") }
        }
        print("")
        print("---------")
    }
}
