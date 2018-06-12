//
//  cpu_helper.swift
//  GameBoy
//
//  Created by Teo Sartori on 31/05/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

// Extension defining helper functions
extension CPU {
    
    func getVal8(for register: ArgType) throws -> UInt8 {
        switch register {
        case .A: return A
        case .B: return B
        case .C: return C
        case .D: return D
        case .E: return E
        case .H: return H
        case .L: return L
            
        case .BCptr: return read8(at: BC)
        case .DEptr: return read8(at: DE)
        case .HLptr: return read8(at: HL)
            
        case .HLptrInc:
            let oldHL = read8(at: HL)
            try inc16(argType: .HL)
            return oldHL
        case .HLptrDec:
            let oldHL = read8(at: HL)
            try dec16(argType: .HL)
            return oldHL
            
        case .Cptr: return read8(at: 0xFF00 + UInt16(C))
        case .i8: return read8(at: PC)
        case .i16ptr:
            let dest = try getVal16(for: .i16)
            return read8(at: dest)
            
        case .u3_0: return 0
        case .u3_1: return 1
        case .u3_2: return 2
        case .u3_3: return 3
        case .u3_4: return 4
        case .u3_5: return 5
        case .u3_6: return 6
        case .u3_7: return 7
            
        default: throw CPUError.UnknownRegister
        }
    }
    
    func set(val: UInt8, for register: ArgType) throws {
        switch register {
        case .A: A = val
        case .B: B = val
        case .C: C = val
        case .D: D = val
        case .E: E = val
        case .H: H = val
        case .L: L = val
            
        // Write value to memory pointed to by the given register
        case .BCptr: write(at: BC, with: val)
        case .DEptr: write(at: DE, with: val)
        case .HLptr: write(at: HL, with: val)
            
        case .HLptrInc: write(at: HL, with: val) ; try inc16(argType: .HL)
        case .HLptrDec: write(at: HL, with: val) ; try dec16(argType: .HL)
            
        case .Cptr: write(at: 0xFF00 + UInt16(C), with: val)
            
        case .i8: write(at: PC, with: val)
        
        case .i16ptr: // Load an 8 bit value into a destination
            let dest = try getVal16(for: .i16)
            write(at: dest, with: val)

        default: throw CPUError.UnknownRegister
        }
    }
    
    func getVal16(for register: ArgType) throws -> UInt16 {
        switch register {
        case .AF: return AF
        case .BC: return BC
        case .DE: return DE
        case .HL: return HL
        case .SP: return SP
            
        case .SPptr: return read16(at: SP)
            
        case .i16: return read16(at: PC)
            
        default: throw CPUError.UnknownRegister
        }
    }
    
    func set(val: UInt16, for register: ArgType) throws {
        switch register {
        case .AF: AF = val
        case .BC: BC = val
        case .DE: DE = val
        case .HL: HL = val
        case .SP: SP = val
            
        case .SPptr: write(at: SP, with: val)
            
        // Load a 16 bit value into a destination, LD (i16), SP
        case .i16ptr:
            let dest = try getVal16(for: .i16)
            write(at: dest, with: val)
            
            
        default: throw CPUError.UnknownRegister
        }
    }
    
    // Wrappers to increment PC as appropriate
    func read8(at location: UInt16) -> UInt8 {
        let val = ram.read8(at: location)
        incPc()
        return val
    }
    
    func read16(at location: UInt16) -> UInt16 {
        let val = ram.read16(at: location)
        incPc(2)
        return val
    }
    
    func write(at location: UInt16, with value: UInt8) {
        ram.write(at: location, with: value)
        // writes don't increment PC
    }
    
    func write(at location: UInt16, with value: UInt16) {
        let msb = UInt8(value >> 8)
        let lsb = UInt8(value & 0xFF)
        ram.write(at: location, with: msb)
        ram.write(at: location+1, with: lsb)
        // writes don't increment PC
    }
    
    func incPc(_ bytes: UInt16=1) {
        PC = (PC &+ bytes)
    }
    
    func halfCarryOverflow(term1: UInt8, term2: UInt8) -> Bool {
        return (((term1 & 0xF) + (term2 & 0xF)) & 0x10) == 0x10
    }
    
    func halfCarryUnderflow(term1: UInt8, term2: UInt8) -> Bool {
        // If the lower nibble of term1 is less than the lower nibble of term2 it will half carry
        return (term1 & 0xF) < (term2 & 0xF)
    }
    
    func halfCarryOverflow(term1: UInt16, term2: UInt16) -> Bool {
        return (((term1 & 0xFFF) + (term2 & 0xFFF)) & 0x1000) == 0x1000
    }
    
    /// Check for the given conditions, if any.
    ///
    /// - Parameter arg: the condition (or a non conditional argument type)
    /// - Returns:
    ///     true if the arg was a condition type and the condition was satisifed
    ///     false if the arg was a condition type and the condition was not satisfied
    ///     nil if the arg was not a condition type
    func checkCondition(for arg: ArgType) -> Bool? {
        switch arg {
        case .Carry:   return F.C == true
        case .NoCarry: return F.C == false
        case .Zero:    return F.Z == true
        case .NotZero: return F.Z == false
        default: return nil
        }
    }

    func isFlagSet(for bit: UInt8, in register: UInt8) -> Bool {
        return ((register >> bit) & 0x1) == 0x1
    }
    
    func setFlag(for bit: UInt8, in register: UInt8) -> UInt8 {
        return register | (1 << bit)
    }
    
    func toggleFlag(for bit: UInt8, in register: UInt8) -> UInt8 {
        return register ^ (1 << bit)
    }
}
