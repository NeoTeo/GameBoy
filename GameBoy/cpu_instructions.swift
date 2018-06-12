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
    
    func adc(argTypes: (ArgType, ArgType)) throws {
        
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
    
    func add16_16(argTypes: (ArgType, ArgType)) throws {
        let t1 = try getVal16(for: argTypes.0)
        let t2 = try getVal16(for: argTypes.1)
        let (result, overflow) = t1.addingReportingOverflow(t2)
        try set(val: result, for: argTypes.0)
        
        //        F.Z = (result == 0) // does not affect
        F.N = false
        F.H = halfCarryOverflow(term1: t1, term2: t2)
        F.C = overflow
    }
    
    func add8_8(argTypes: (ArgType, ArgType)) throws {
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
    func and(argTypes: (ArgType, ArgType)) throws {
        let t1 = try getVal8(for: argTypes.0)
        let t2 = try getVal8(for: argTypes.1)
        let result = t1 & t2
        try set(val: result, for: argTypes.0)
        
        F.Z = (result == 0)
        F.N = false
        F.H = true
        F.C = false
    }

    // Push the address after the CALL instruction (PC+3) onto the stack and
    // jump to the label in source arg. Can also take conditions in target arg.
    func call(argTypes: (ArgType, ArgType)) throws {
        let targetArg = argTypes.0
        let sourceArg = argTypes.1
        
        // If checkCondition returns nil there was no condition so we ignore it.
        // If there was a condition we only continue if it passed.
        if let passCondition = checkCondition(for: targetArg) {
            guard passCondition == true else { return }
        }
        
        // put the address after the CALL instruction onto the stack
        let returnAddress = PC &+ 3
        try set(val: returnAddress, for: .BC)
        try push(argTypes: (.noReg, .BC))
        
        let callAddress = try getVal16(for: sourceArg)
        PC = callAddress
    }

    func cb() throws {
        // Read the next byte as an opcode and return
    }
    
    // Complement Carry flag
    func ccf() {
        F.N = false
        F.H = false
        F.C = !F.C
    }
    
    // Perform a subtraction of the source register from the target register.
    // Set the flags but don't keep the result.
    func cp(argTypes: (ArgType, ArgType)) throws {
        let t1 = try getVal8(for: argTypes.0) // Always A so could be optimised away.
        let t2 = try getVal8(for: argTypes.1)
        let (result, overflow) = t1.subtractingReportingOverflow(t2)
        
        F.Z = (result == 0)
        F.N = true
        F.H = halfCarryUnderflow(term1: t1, term2: t2)
        F.C = overflow
    }

    // Complement A (accumulator)
    func cpl() {
        A = ~A
        
        F.N = true
        F.H = true
    }
    
    /// Decimal Adjust A (accumulator)
    /// Use the content of the flags to adjust the A register.
    /// If the least significant four bits of A contain an non-BCD (ie > 9) or
    /// the H flag is set then add 0x06 to the A register.
    /// Then, if the four most significant bits are > 9 (or the C flag is set)
    /// then 0x60 is added to the A register.
    /// If the N register is set in any of these cases then we must subtract rather than add.
    func daa() {
        
        var overflow: Bool = false
        if ((A & 0x0F) > 0x09) || (F.H == true) {
            
            (A, overflow) = (F.N == true) ? A.subtractingReportingOverflow(0x06) : A.addingReportingOverflow(0x06)
            F.C = F.C || overflow
            //            A = (F.N == true) ? A &- 0x06 : A &+ 0x06 }
        }

        if ((A >> 4) > 0x09) || (F.C == true) {
            (A, overflow) = (F.N == true) ? A.subtractingReportingOverflow(0x60) : A.addingReportingOverflow(0x60)
            F.C = F.C || overflow
//            A = (F.N == true) ? A &- 0x60 : A &+ 0x60
        }
        
        F.Z = (A == 0)
        F.H = false
    }
    
    // DEC A, B, C, D, E, H, L, (HL)
    func dec8(argType: ArgType) throws {
        var n: UInt8
        
        // FIXME: This is already part of the getVal8. Remove special case!
        // pointer indirection special case
//        if argType == .HLptr {
//
//            let addr = try getVal16(for: .HL)
//            n = read8(at: addr)
//            n = n &- 1
//            write(at: addr, with: n)
//
//        } else {
        
            n = try getVal8(for: argType)
            n = n &- 1
            try set(val: n, for: argType)
//        }
        
        F.Z = (n == 0)
        F.H = (n == 0xf) // H set if no borrow from bit 4 ?
        F.N = true // N set to 1
    }
    
    // DEC BC, DE, HL, SP
    func dec16(argType: ArgType) throws {
        var nn = try getVal16(for: argType)
        nn = nn &- 1
        try set(val: nn, for: argType)
    }

    // Disable interrupts
    func di() {
        IME = false
    }
    
    // Interrupt enable
    func ei() {
        IME = true
    }

    func halt() {
        print("CPU in low power mode.")
    }
    
    // INC A, B, C, D, E, H, L, (HL)
    // Flags affected:
    // Z - Set if result is zero.
    // N - Reset.
    // H - Set if carry from bit 3.
    // C - Not affected.
    func inc8(argType: ArgType) throws {
        
        var n: UInt8
        // FIXME: Already handled by getVal8. Remove this
        // pointer indirection special case
//        if argType == .HLptr {
//
//            let addr = try getVal16(for: .HL)
//            n = read8(at: addr)
//            n = n &+ 1
//            write(at: addr, with: n)
//        } else {
        
            n = try getVal8(for: argType)
            // increment n register and wrap to 0 if overflowed.
            n = n &+ 1
            try set(val: n, for: argType)
//        }
        // Set F register correctly
        F.Z = (n == 0)
        F.H = (n == 0x10) // If n was 0xf then we had carry from bit 3.
        F.N = false
        
    }
    
    // INC BC, DE, HL, SP
    // Flags unaffected
    func inc16(argType: ArgType) throws {
        var nn = try getVal16(for: argType)
        nn = nn &+ 1
        try set(val: nn, for: argType)
    }
    
    func jr(argTypes: (ArgType, ArgType)) throws {
        let targetArg = argTypes.0
        let sourceArg = argTypes.1
        var offset: UInt8 = 0
        
        if let passCondition = checkCondition(for: targetArg) {
            // if we have a conditional jump and the condition is satisfied we use sourceArg as offset
            guard passCondition == true else { return }
            offset = try getVal8(for: sourceArg)
        } else {
            // there was no condition so the targetArg is the offset
            offset = try getVal8(for: targetArg)
        }
        
        // The offset is a (-128 to 127) value. Treat as 2's complement.
        let isNegative = (offset & 0x80) == 0x80
        let tval = Int(offset & 0x7f)
        let newPc = UInt16(Int(PC) + (isNegative ? -(128 - tval) : tval))
        // Jump to PC + offset
        guard newPc < ram.size, newPc >= 0 else {
            throw CPUError.RamError
        }
        PC = newPc
    }
    
    func ld8_8(argTypes: (ArgType, ArgType)) throws {
        var n: UInt8
        let source = argTypes.1
        let target = argTypes.0
        
        n = try getVal8(for: source)
        
        try set(val: n, for: target)
    }
    
    // Load a 16 bit source into a 16 bit destination
    // Flags unaffected.
    func ld16_16(argTypes: (ArgType, ArgType)) throws {
        let source = argTypes.1
        let target = argTypes.0
        
        let srcVal = try getVal16(for: source)
        try set(val: srcVal, for: target)
    }

    func or(argTypes: (ArgType, ArgType)) throws {
        let t1 = try getVal8(for: argTypes.0) // Always A. Can be optimized away.
        let t2 = try getVal8(for: argTypes.1)
        let result = t1 | t2
        try set(val: result, for: argTypes.0)
        
        F.Z = (result == 0)
        F.N = false
        F.H = false
        F.C = false
    }
    
    func pop(argTypes: (ArgType, ArgType)) throws {
        
        // Read the two bytes at the address pointed to by the SP
        let t1 = try getVal16(for: .SPptr)
        // FIXME: Additional checking for stack pointer overflow?
        SP = SP &+ 2
        
        try set(val: t1, for: argTypes.0)
    }
    
    func push(argTypes: (ArgType, ArgType)) throws {
        let val = try getVal16(for: argTypes.1)
        try set(val: val, for: .SPptr)
        SP = SP &- 2
    }
    
    // Rotate destination register(or value pointed to by it) left through carry.
    // C <- [7 <- 0] <- C
    func rl(argTypes: (ArgType, ArgType)) throws {
        let regVal = try getVal8(for: argTypes.0)
        let oldCarry: UInt8 = (F.C == true) ? 0x01 : 0x00
        let newCarry = (regVal >> 7) == 0x01
        let result = (regVal << 1) | oldCarry
        try set(val: result, for: argTypes.0)
        F.C = newCarry
        F.N = false
        F.H = false
        F.Z = (result == 0x00)
    }

    
    // Rotate register A left through carry.
    // C <- [7 <- 0] <- C
    func rla() throws {
        let oldCarry: UInt8 = (F.C == true) ? 0x01 : 0x00
        let newCarry = (A >> 7) == 0x01
        A = (A << 1) | oldCarry
        F.C = newCarry
        F.N = false
        F.H = false
        F.Z = false
    }

    // Rotate register A left.
    // C <- [7 <- 0] <- [7]
    func rlca() throws {
        let carry: UInt8 = (A >> 7)
        F.C = (carry == 0x01)
        A = (A << 1) + carry
        F.Z = false
        F.N = false
        F.H = false
    }

    // CB prefix instruction
    // RLC A, B, C, D, E, H, L, (HL)
    // Rotate left
    func rlc(argType: ArgType) throws {
        let reg = try getVal8(for: argType)
        let carry: UInt8 = (reg >> 7)
        F.C = (carry == 0x01)
        try set(val: ((reg << 1) | carry), for: argType)
        F.Z = (reg == 0x00)
        F.N = false
        F.H = false
    }

    // Rotate target register right through carry.
    // C -> [7 -> 0] -> C
    func rr(argTypes: (ArgType, ArgType)) throws {
        let oldCarry: UInt8 = (F.C == true) ? 0x80 : 0x00
        let regVal = try getVal8(for: argTypes.0)
        let newCarry = (regVal & 0x01) == 0x01
        let newVal = (regVal >> 1) | oldCarry
        try set(val: newVal, for: argTypes.0)
        
        F.C = newCarry
        F.N = false
        F.H = false
        F.Z = (newVal == 0x00)
    }

    // Rotate register A right through carry.
    // C -> [7 -> 0] -> C
    func rra() throws {
        let oldCarry: UInt8 = (F.C == true) ? 0x80 : 0x00
        let newCarry = (A & 0x01) == 0x01
        A = (A >> 1) | oldCarry
        F.C = newCarry
        F.N = false
        F.H = false
        F.Z = false
    }
    
    // Rotate register A right.
    // [0] -> [7 -> 0] -> C
    func rrca() throws {
        let carry = (A & 0x01) == 0x01
        A = (A >> 1) | (carry ? 0x80 : 0x00)
        F.C = carry
        F.N = false
        F.H = false
        F.Z = false
    }

    func sbc(argTypes: (ArgType, ArgType)) throws {
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
    
    // Set Carry Flag
    func scf() {
        F.C = true
        F.N = false
        F.H = false
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
    func sub8_8(argTypes: (ArgType, ArgType)) throws {
        let t1 = try getVal8(for: argTypes.0) // Always A so could be optimised away.
        let t2 = try getVal8(for: argTypes.1)
        let (result, overflow) = t1.subtractingReportingOverflow(t2)
        try set(val: result, for: argTypes.0)
        F.Z = (result == 0)
        F.N = true
        F.H = halfCarryUnderflow(term1: t1, term2: t2)
        F.C = overflow
    }
    
    func xor(argTypes: (ArgType, ArgType)) throws {
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

// CB prefix instructions
extension CPU {
    
    func bit(argTypes: (ArgType, ArgType)) throws {
        let sourceVal = try getVal8(for: argTypes.1)
        // Get the immediate value for the bit to test and mask in the bottom three bits
        let bitToTest = try getVal8(for: argTypes.0)//try getVal8(for: argTypes.0) & 0x7
        
        // Set Zero flag if the bit was not set
        F.Z = ((sourceVal >> bitToTest) & 0x01) == 0x0
        F.N = false
        F.H = true
    }
}
