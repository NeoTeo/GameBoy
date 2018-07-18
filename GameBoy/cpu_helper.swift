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
            
        case .BCptr: return try read8(at: BC)
        case .DEptr: return try read8(at: DE)
        case .HLptr: return try read8(at: HL)
            
        case .HLptrInc:
            let oldHL = try read8(at: HL)
            try inc16(argType: .HL)
            return oldHL
        case .HLptrDec:
            let oldHL = try read8(at: HL)
            try dec16(argType: .HL)
            return oldHL
            
        case .HiRamC: return try read8(at: 0xFF00 + UInt16(C))
        case .HiRamI8:
            let val = try getVal8(for: .i8)
            return try read8(at: 0xFF00 + UInt16(val))
            
        case .i8, .s8: return try read8(at: PC, incPC: true)
        case .i16ptr:
            let dest = try getVal16(for: .i16)
            return try read8(at: dest)
            
        case .u3_0: return 0
        case .u3_1: return 1
        case .u3_2: return 2
        case .u3_3: return 3
        case .u3_4: return 4
        case .u3_5: return 5
        case .u3_6: return 6
        case .u3_7: return 7
            
        case .vec00h: return 0x00
        case .vec08h: return 0x08
        case .vec10h: return 0x10
        case .vec18h: return 0x18
        case .vec20h: return 0x20
        case .vec28h: return 0x28
        case .vec30h: return 0x30
        case .vec38h: return 0x38
        
        case .vec40h: return 0x40   // vblank
        case .vec48h: return 0x48   // lcdc status
        case .vec50h: return 0x50   // timer overflow
        case .vec58h: return 0x58   // serial transfer completion
        case .vec60h: return 0x60   // p10-p13 input signal goes low
            
        default:
            throw CPUError.UnknownRegister
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
            
        case .HiRamC: write(at: 0xFF00 + UInt16(C), with: val)
        case .HiRamI8:
            let offset = try getVal8(for: .i8)
            write(at: 0xFF00 + UInt16(offset), with: val)
            
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
            
        case .SPptr: return try read16(at: SP)
//        case .SPi8:
//            // Read the i8 first
//            let val = try read8(at: PC, incPC: true)
//            return SP + UInt16(val)
            
        case .i16:
            return try read16(at: PC, incPC: true)
            
//        case .s8:   // Special case for ADD SP, i8
//            return UInt16(try read8(at: PC, incPC: true))
            
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
    func read8(at location: UInt16, incPC: Bool = false) throws -> UInt8 {
        let val = try mmu.read8(at: location)
        if incPC == true { incPc() }
        return val
    }
    
    func read16(at location: UInt16, incPC: Bool = false) throws -> UInt16 {
        let val = try mmu.read16(at: location)
        if incPC == true { incPc(2) }
        
        return val
    }
    
    func write(at location: UInt16, with value: UInt8) {
        mmu.write(at: location, with: value)
        // writes don't increment PC
    }
    
    func write(at location: UInt16, with value: UInt16) {
        let msb = UInt8(value >> 8)
        let lsb = UInt8(value & 0xFF)
        mmu.write(at: location, with: lsb)
        mmu.write(at: location+1, with: msb)
        // writes don't increment PC
    }
    
    func incPc(_ bytes: UInt16=1) {
        PC = (PC &+ bytes)
    }
    
//    func carryOverflow(t1: UInt8, t2: Int) -> (UInt8, Bool) {
//        // perform addition (or subtraction if t2 is negative) and wrap result.
//        let result = UInt8((Int(t1) + t2) & 0xFF)
//        let overflow =
//    }
    
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

    func halfCarryUnderflow(term1: UInt16, term2: UInt16) -> Bool {
        // If the lower nibble of term1 is less than the lower nibble of term2 it will half carry
        return (term1 & 0xFFF) < (term2 & 0xFFF)
    }

//    func signedVal(from value: UInt8) -> Int {
//        // The value is a (-128 to 127) value. Treat as 2's complement.
////        let isNegative = (value & 0x80) == 0x80
////        let tval = Int(value & 0x7f)
////
////        return isNegative ? -(128 - tval) : tval
//        return Int(value & 0x7f) - Int(value & 0x80)
//    }
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
}

// Debug helper functions
extension CPU {
    
    // print the values of the registers
    func debugRegisters() {
        print(String(format: "AF: %2X", AF))
        print(String(format: "BC: %2X", BC))
        print(String(format: "DE: %2X", DE))
        print(String(format: "HL: %2X", HL))
        print("-----------------")
        print(String(format: "SP: %2X", SP))
        print(String(format: "PC: %2X", PC))
        print("-----------------")
        print("F: \(F)")
        print("IME: \(IME)")
        print(String(format: "IF: %2X – IE: %2X", mmu.IF, mmu.IE))
        let lcdc = mmu.getValue(for: .lcdc)
        let stat = mmu.getValue(for: .stat)
        print(String(format: "lcdc: %2X – stat: %2X", lcdc, stat))
        let ly = mmu.getValue(for: .ly)
        print(String(format: "ly: %2X", ly))
    }
}

// Global helpers

func signedVal(from value: UInt8) -> Int {
    return Int(value & 0x7f) - Int(value & 0x80)
}

func isSet(bit: UInt8, in byte: UInt8) -> Bool {
    return ((byte >> bit) & 0x1) == 0x1
}

func set(bit: UInt8, in byte: UInt8) -> UInt8 {
    return byte | (1 << bit)
}

func clear(bit: UInt8, in byte: UInt8) -> UInt8 {
    return (byte & ~(1 << bit))
}

func toggle(bit: UInt8, in byte: UInt8) -> UInt8 {
    return byte ^ (1 << bit)
}

struct OpenBuffer<T> {
    fileprivate var array: [T?]
    public let capacity: Int
    var count: Int = 0
    var index = 0
    
    public init(capacity: Int) {
        array = Array<T?>(repeating: nil, count: capacity)
        self.capacity = capacity
    }
    
    public mutating func push(element: T) {
        index = (index + 1) % capacity
        array[index] = element
    }
    
    public func debugPrint(handler: ((T)->Void)? ) {
        for i in 0 ..< capacity {
            
            let idx = (index + i) % capacity
            guard let element = array[idx] else { continue }
            
            if handler == nil {
                print("\(String(describing: element))")
            } else {
                handler?(element)
            }
        }
    }
}
