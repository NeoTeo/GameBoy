//
//  cpu_instructions.swift
//  GameBoy
//
//  Created by Teo Sartori on 31/05/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

// Extension defining instructions
// Terms:
// n an 8 bit value, nn a 16 bit value
extension CPU {
    
    func adc(argTypes: (RegisterType, RegisterType)) throws {
        
        let t1 = try getVal8(for: argTypes.0)
        let t2 = try getVal8(for: argTypes.1)
        
        // Store the C flag before it is changed.
        let oldC: UInt8 = F.C == true ? 1 : 0
        
        // First add the registers keeping track of the carrys
        let (res1, overflow1) = t1.addingReportingOverflow(t2)
        let H1 = halfCarryOverflow(term1: t1, term2: t2)
        // Then add the old carry and track the resulting carrys
        let (result, overflow2) = res1.addingReportingOverflow(oldC)
        let H2 = halfCarryOverflow(term1: res1, term2: oldC)
        
        print("overflow1: \(overflow1) and overflow2: \(overflow2)")
        try set(val: result, for: argTypes.0)
        
        F.Z = (result == 0)
        F.N = false
        F.H = H1 || H2
        F.C = overflow1 || overflow2
    }
    
    func sbc(argTypes: (RegisterType, RegisterType)) throws {
        let t1 = try getVal8(for: argTypes.0) // Always A so could be optimised away.
        let t2 = try getVal8(for: argTypes.1)
        
        // Store the C flag before it is changed.
        let oldC: UInt8 = F.C == true ? 1 : 0

        let (res1, overflow1) = t1.subtractingReportingOverflow(t2)
        let H1 = halfCarryUnderflow(term1: t1, term2: t2)
        
        let (result, overflow2) = res1.subtractingReportingOverflow(oldC)
        let H2 = halfCarryUnderflow(term1: res1, term2: oldC)

        try set(val: result, for: argTypes.0)
        
        F.Z = (result == 0)
        F.N = true
        F.H = H1 || H2
        F.C = overflow1 || overflow2
        
    }

    func add16_16(argTypes: (RegisterType, RegisterType)) throws {
        let t1 = try getVal16(for: argTypes.0)
        let t2 = try getVal16(for: argTypes.1)
        let (result, overflow) = t1.addingReportingOverflow(t2)
        try set(val: result, for: argTypes.0)
        
        //        F.Z = (result == 0) // does not affect
        F.N = false
        F.H = halfCarryOverflow(term1: t1, term2: t2)
        F.C = overflow
    }
    
    func add8_8(argTypes: (RegisterType, RegisterType)) throws {
        let t1 = try getVal8(for: argTypes.0)
        let t2 = try getVal8(for: argTypes.1)
        let (result, overflow) = t1.addingReportingOverflow(t2)
        try set(val: result, for: argTypes.0)
        
        F.Z = (result == 0)
        F.N = false
        F.H = halfCarryOverflow(term1: t1, term2: t2)
        F.C = overflow
    }
    
    // Bitwise AND between the value in the register and the A register
    func and(argTypes: (RegisterType, RegisterType)) throws {
        let t1 = try getVal8(for: argTypes.0)
        let t2 = try getVal8(for: argTypes.1)
        let result = t1 & t2
        try set(val: result, for: argTypes.0)
        
        F.Z = (result == 0)
        F.N = false
        F.H = true
        F.C = false
    }
    
    // Perform a subtraction of the source register from the target register.
    // Set the flags but don't keep the result.
    func cp(argTypes: (RegisterType, RegisterType)) throws {
        let t1 = try getVal8(for: argTypes.0) // Always A so could be optimised away.
        let t2 = try getVal8(for: argTypes.1)
        let (result, overflow) = t1.subtractingReportingOverflow(t2)
        
        F.Z = (result == 0)
        F.N = true
        F.H = halfCarryUnderflow(term1: t1, term2: t2)
        F.C = overflow
    }

    func halt() {
        print("CPU in low power mode.")
    }

    func stop() {
        print("CPU in very low power mode.")
    }
    
    /*
     SUB A,r8
     
     Subtract the value in source regisrer from target register and store result in target register.
     Z: Set if result is 0.
     N: 1
     H: Set if no borrow from bit 4.
     C: Set if no borrow (set if source register > target register).
 */
    func sub8_8(argTypes: (RegisterType, RegisterType)) throws {
        let t1 = try getVal8(for: argTypes.0) // Always A so could be optimised away.
        let t2 = try getVal8(for: argTypes.1)
        let (result, overflow) = t1.subtractingReportingOverflow(t2)
        try set(val: result, for: argTypes.0)
        F.Z = (result == 0)
        F.N = true
        F.H = halfCarryUnderflow(term1: t1, term2: t2)
        F.C = overflow
    }

    
    func rlca() throws {
        F.C = (A >> 7) == 1
        A = A << 1
        F.Z = false
        F.N = false
        F.H = false
    }
    
    // CB prefix instruction
    // RLC A, B, C, D, E, H, L, (HL)
    // Rotate left
    func rlc(argType: RegisterType) throws {
        let reg = try getVal8(for: argType)
        F.C = (reg >> 7) == 1
        try set(val: reg << 1, for: argType)
        F.Z = (reg == 0)
        F.N = false
        F.H = false
    }
    
    func ld8_8(argTypes: (RegisterType, RegisterType)) throws {
        var n: UInt8
        let source = argTypes.1
        let target = argTypes.0
        
        if source == .i8 {
            n = read8(at: PC)
            incPc() // reading from RAM increases the PC
        } else {
            n = try getVal8(for: source)
        }
        
        try set(val: n, for: target)
    }
    
    // Load a 16 bit source into a 16 bit destination
    // Flags unaffected.
    func ld16_16(argTypes: (RegisterType, RegisterType)) throws {
        let source = argTypes.1
        let target = argTypes.0
        
        let srcVal = try getVal16(for: source)
        try set(val: srcVal, for: target)
    }

    // INC A, B, C, D, E, H, L, (HL)
    // Flags affected:
    // Z - Set if result is zero.
    // N - Reset.
    // H - Set if carry from bit 3.
    // C - Not affected.
    func inc8(argType: RegisterType) throws {
        
        var n: UInt8
        // pointer indirection special case
        if argType == .HLptr {
            
            let addr = try getVal16(for: .HL)
            n = read8(at: addr)
            n = n &+ 1
            write(at: addr, with: n)
        } else {
            
            n = try getVal8(for: argType)
            // increment n register and wrap to 0 if overflowed.
            n = n &+ 1
            try set(val: n, for: argType)
        }
        // Set F register correctly
        F.Z = (n == 0)
        F.H = (n == 0x10) // If n was 0xf then we had carry from bit 3.
        F.N = false
        
    }
    
    // INC BC, DE, HL, SP
    // Flags unaffected
    func inc16(argType: RegisterType) throws {
        var nn = try getVal16(for: argType)
        nn = nn &+ 1
        try set(val: nn, for: argType)
    }
    
    // DEC A, B, C, D, E, H, L, (HL)
    func dec8(argType: RegisterType) throws {
        var n: UInt8
        
        // pointer indirection special case
        if argType == .HLptr {
            
            let addr = try getVal16(for: .HL)
            n = read8(at: addr)
            n = n &- 1
            write(at: addr, with: n)
            
        } else {
            
            n = try getVal8(for: argType)
            n = n &- 1
            try set(val: n, for: argType)
        }
        
        F.Z = (n == 0)
        F.H = (n == 0xf) // H set if no borrow from bit 4 ?
        F.N = true // N set to 1
    }
    
    // DEC BC, DE, HL, SP
    func dec16(argType: RegisterType) throws {
        var nn = try getVal16(for: argType)
        nn = nn &- 1
        try set(val: nn, for: argType)
    }
    
    func or(argTypes: (RegisterType, RegisterType)) throws {
        let t1 = try getVal8(for: argTypes.0) // Always A. Can be optimized away.
        let t2 = try getVal8(for: argTypes.1)
        let result = t1 | t2
        try set(val: result, for: argTypes.0)
        
        F.Z = (result == 0)
        F.N = false
        F.H = false
        F.C = false
    }
    
    func xor(argTypes: (RegisterType, RegisterType)) throws {
        let t1 = try getVal8(for: argTypes.0) // Always A. Can be optimized away.
        let t2 = try getVal8(for: argTypes.1)
        let result = t1 ^ t2
        try set(val: result, for: argTypes.0)
        
        F.Z = (result == 0)
        F.N = false
        F.H = false
        F.C = false
    }
}
