//
//  cpu.swift
//  GameBoy
//
//  Created by Teo Sartori on 22/10/2016.
//  Copyright © 2016 Matteo Sartori. All rights reserved.
//

import Foundation

struct CPU {
    var PC: UInt16 = 0      // Program Counter
    var SP: UInt16 = 0      // Stack Pointer
    
    /// registers
    var A: UInt8 = 0
    var B: UInt8 = 0
    var C: UInt8 = 0
    var D: UInt8 = 0
    var E: UInt8 = 0
    
    var H: UInt8 = 0
    var L: UInt8 = 0
    
    /// Bit 7 = Zero, 6 = Subtract, 5 = Half carry, 4 = Carry
    struct Flags {
        var Z: Bool = false     /// Zero
        var N: Bool = false     /// Subtract/Negative
        var H: Bool = false     /// Half carry
        var C: Bool = false     /// carry
    }
    
    var F: Flags = Flags()
    
    func dataAtPc(_ ram: [UInt8]) -> UInt8 {
        return ram[Int(PC)]
    }
}

struct MEMORY {
    let ram_size: UInt16// in bytes
    var ram: [UInt8]
    
    init(size: UInt16) {
        ram_size = size
        ram = Array(repeating: 0, count: Int(ram_size))
    }
}

struct SYSTEM {
    
    var cpu: CPU
    var memory: MEMORY
    
    init() {
        memory = MEMORY(size: 8192)
        cpu = CPU()
    }
}

func start(system: inout SYSTEM) {
    
    var interrupt = 0
    
    func incPc() {
        system.cpu.PC += 1
    }
    
    var BC: UInt16 {
        get { return (UInt16(system.cpu.B) << 8) | UInt16(system.cpu.C) }
        set {
            system.cpu.C = UInt8(newValue & 0xFF)
            system.cpu.B = UInt8(newValue >> 8)
        }
    }
    var DE: UInt16 {
        get { return (UInt16(system.cpu.D) << 8) | UInt16(system.cpu.E) }
        set {
            system.cpu.E = UInt8(newValue & 0xFF)
            system.cpu.D = UInt8(newValue >> 8)
        }
    }
    var HL: UInt16 {
        get { return (UInt16(system.cpu.H) << 8) | UInt16(system.cpu.L) }
        set {
            system.cpu.L = UInt8(newValue & 0xFF)
            system.cpu.H = UInt8(newValue >> 8)
        }
    }

    func readData16(at location: UInt16) -> UInt16 {
        let msb = system.memory.ram[Int(location)]
        let lsb = system.memory.ram[Int(location+1)]
        return (UInt16(msb) << 8) | UInt16(lsb)
    }

    func readData8(at location: UInt16) -> UInt8 {
            return system.memory.ram[Int(location)]
    }
    
    func writeRam(at location: UInt16, with value: UInt8) {
        system.memory.ram[Int(location)] = value
    }
    
    repeat {
        /// Read from ram
        let opcode = readData8(at: system.cpu.PC)
        
        /// We've read the opcode so move on to next address.
        incPc()
        
        /** interpret data/instruction
            Each opcode can affect the registers, the RAM and the interrupts
        **/
        switch opcode {
        case 0x00:  /// NOP
            incPc()
            
        case 0x01:  /// LD BC, d16
            system.cpu.B = readData8(at: system.cpu.PC)
            incPc()
            system.cpu.C = readData8(at: system.cpu.PC)
            
        case 0x02:  /// LD (BC), A, load location at BC with register A
            writeRam(at: BC, with: system.cpu.A)
        
        case 0x03:  /// INC BC
            BC += 1
        
        case 0x04:  /// INC B
            system.cpu.B += 1
            
        case 0x05:  /// DEC B
            system.cpu.B -= 1
            
        case 0x06:  /// LD B, d8
            system.cpu.B = readData8(at: system.cpu.PC)
            
        default:
            interrupt = 1
            break
        }
    } while interrupt == 0
}

