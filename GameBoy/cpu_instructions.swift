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
        
//        print("overflow1: \(overflow1) and overflow2: \(overflow2)")
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
        
        // Special case for ADD SP, i8
        if argTypes.0 == .SP { F.Z = false }
        
        F.N = false
        F.H = halfCarryOverflow(term1: t1, term2: t2)
        F.C = overflow
    }
    
    func add8_8(argTypes: (ArgType, ArgType)) throws {
        let t1 = try getVal8(for: argTypes.0)
        let t2 = try getVal8(for: argTypes.1)
        let (result, overflow) = t1.addingReportingOverflow(t2)
        try set(val: result, for: argTypes.0)
        
        // As a special case, if the instruction is ADD SP, i8 we reset the Z flag.
        F.Z = (argTypes.0 == .SP) ? false : (result == 0)
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
        let conditionArg = argTypes.0
        let addressArg = argTypes.1
        // Make sure we get the call address (so we inc the PC if the arg is an
        // immediate) before we have a chance to fail the condition.
        let callAddress = try getVal16(for: addressArg)
        
        // If checkCondition returns nil there was no condition so we ignore it.
        // If there was a condition we only continue if it passed.
        if let passCondition = checkCondition(for: conditionArg) {
            guard passCondition == true else { return }
        }
        
        // put the address after the CALL instruction onto the stack
        let returnAddress = PC
        
        SP = SP &- 2
        try set(val: returnAddress, for: .SPptr)
        
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
    /// Use the content of the flags to adjust the A register after an ADD/ADC or SUB/SBC
    /// If the least significant four bits of A contain an non-BCD (ie > 9) or
    /// the H flag is set then add 0x06 to the A register.
    /// Then, if the four most significant bits are > 9 (or the C flag is set)
    /// then 0x60 is added to the A register.
    /// If the N register is set in any of these cases then we must subtract rather than add.
    
    // In BCD each nibble (4 bits of a byte) represents a value between 0 and 9.
    // Adding two BCD values produces a valid result but the result, if above 9, is not in BCD itself.
    // Eg. 7 (0111) + 7 (0111) = 14 (1110)
    // To convert to BCD we must add 6 (0110) to the result:
    // 14 (1110) + 6 (0110) = 20 (00010100) which is 14 in BCD.
    // ** So the first rule is that whenever the resulting value is > 9 we should add 6 to it. **
    
    // Addition of two digits in BCD may yield results below 9 that are still not correct BCD.
    // To know when to use the first rule of adding 6 we need to consider the carry for each nibble.
    // If the addition of the least significant nibble produced a carry (aka half-carry) we need to add 6.
    // If the addition of the most significant nibble _produced_a_carry_ we need to add 6 to that
    // nibble (or 96 to the whole byte).
    // Eg. 18 (0001 1000 in BCD) + 29 (0010 1001 in BCD) = 65 (0100 0001) or 41 in BCD which is wrong.
    // The addition of the 8 (1000 in BCD) and the 9 (1001 in BCD) produces a (half) carry:
    // 1000 + 1001 = [1]0001
    // To convert the result to BCD we must add 6 to the least significant nibble:
    // 0001 + 0110 = 0111
    // In this case the addition of the most significant nibble was neither > 9 nor did it produce a
    // a carry so it is already in valid BCD.
    // So the rules are: If either nibble is > 9 or has produced a carry then that nibble needs to add 6.
    
    // Subtraction works on the two's complement (invert and add 1) of the whole byte being subtracted.
    //
    // Huge HT to this blog post: ipfs.io/ipfs/QmQpaFJjaLD1zf5F6uEKZ31LNQTyMCS6uUQsAb2naBNJcX

    func daa() {
        
        var overflow: Bool = false
        var correction = 0
        var value = Int(A)
        
        if ((F.N == false) && (A & 0x0F) > 0x09) || (F.H == true) {
            correction = 0x06
        }

        if ((F.N == false) && (A  > 0x99)) || (F.C == true) {
            correction |= 0x60
            overflow = true
        }
        
        value += (F.N == true) ? -correction : correction
        
        A = UInt8(value & 0xFF)
        F.C = F.C || overflow
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
    
    // Jump to the address given in the target argument. When there is a condition in the source arg
    // the jump will only occur if the condition is satisfied.
    func jp(argTypes: (ArgType, ArgType)) throws {
        let conditionArg = argTypes.0
        let addressArg = argTypes.1
        
        
        let address = try getVal16(for: addressArg)
        // Check if we have a conditional jump and the condition is satisfied.
        if let passCondition = checkCondition(for: conditionArg) {
            // skip after we get the val to ensure that we've incremented the PC
            // if an immediate value was accessed.
            guard passCondition == true else { return }
        }
        
        PC = address
    }
    
    // Jump to an offset from the current PC. When there is a condition in the source arg
    // the jump will only occur if the condition is satisfied.
    func jr(argTypes: (ArgType, ArgType)) throws {
        let conditionArg = argTypes.0
        let offsetArg = argTypes.1
        
        let offset = try getVal8(for: offsetArg)
        
        // Check if we have a conditional jump and the condition is satisfied.
        if let passCondition = checkCondition(for: conditionArg) {
            // Skip only _after_ we get the val to ensure that we've incremented the PC
            // if an immediate value was accessed.
            guard passCondition == true else { return }
        }
        
        
        // The offset is a (-128 to 127) value. Treat as 2's complement.
        let isNegative = (offset & 0x80) == 0x80
        let tval = Int(offset & 0x7f)
        
        let newPc = UInt16(Int(PC) + (isNegative ? -(128 - tval) : tval))
     
        guard newPc < mmu.size, newPc >= 0 else {
            throw CPUError.RamError
        }
        PC = newPc
    }
    
    func ld8_8(argTypes: (ArgType, ArgType)) throws {
        var n: UInt8
        let source = argTypes.1
        let target = argTypes.0
        do {
        n = try getVal8(for: source)
        
        try set(val: n, for: target)
        } catch {
            print("ld Error: \(error)")
        }
    }
    
    // Load a 16 bit source into a 16 bit destination
    // Flags unaffected.
    func ld16_16(argTypes: (ArgType, ArgType)) throws {
        let source = argTypes.1
        let target = argTypes.0
        
        let srcVal = try getVal16(for: source)
        try set(val: srcVal, for: target)
        
    }

    // Special case LD for LDHL (aka. LD HL, SP+r8)
    func ldhl() throws {
        
        // Treat value as signed ranging from -128 to 127
        let offset = signedVal(from: try getVal8(for: .i8))

        ///*
        // This carry and half carry implementation from SO post:
        // ipfs: QmZqMYU4xi3rpNDmHcBw6CNum4JMgcdGQdT6mGvEX2w3nE
        // https://stackoverflow.com/questions/5159603/gbz80-how-does-ld-hl-spe-affect-h-and-c-flags

        var result: UInt16
        var overflow: Bool = false
        var halfCarry: Bool = false

        var sSP = Int(SP) + offset
        
        if offset < 0 {
            // Not sure what is going on with overflow/half carry on subtraction
            overflow = (sSP & 0xFF) <= (SP & 0xFF)
            
            halfCarry = (sSP & 0xF) <= (SP & 0xF)
        } else {
            // Carry if there's an overflow from bit 7 to bit 8.
            overflow = ((SP & 0xFF) + UInt16(offset)) > 0xFF
            
            // Half carry if overflow from bit 3 to bit 4.
            halfCarry = ((SP & 0xF) + (UInt16(offset) & 0xF)) > 0xF
        }
        result = UInt16(sSP)
         
        F.H = halfCarry
        F.C = overflow
        //*/

        /*
        // This carry and half-carry implementation is from
        // https://www.reddit.com/r/EmuDev/comments/692n59/gb_questions_about_halfcarry_and_best/
        // If no carry between bit 3 and 4 then bit 4 of (a ^ offset) will be the same as (a + offset).
        // The xor with the result is to check if they are indeed different (will be set if so).
        // We leave offset as signed because a - b is the same as a + (-b) so it follows that
        // a ^ b is the same as a ^ (-b)
        // The same for carry but comparing against 0x100
        let a = Int(SP)
        let result = a + offset
        F.H = ((a ^ offset ^ result) & 0x10) == 0x10
        F.C = ((a ^ offset ^ result) & 0x100) == 0x100
        */
        
        F.Z = false
        F.N = false

        HL = UInt16(result)
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
        SP = SP &- 2
        try set(val: val, for: .SPptr)
    }
    
    // Set the bit value in in the target argument in the byte referenced in the source argument to 0.
    func res(argTypes: (ArgType, ArgType)) throws {
        let bitToSet = try getVal8(for: argTypes.0)
        let regVal = try getVal8(for: argTypes.1)
        let result = regVal & (0xFF ^ (1 << bitToSet))
        try set(val: result, for: argTypes.1)
        
        // Flags unaffected
    }
    
    /*
     if let passCondition = checkCondition(for: targetArg) {
     // if we have a conditional jump and the condition is satisfied we use sourceArg as offset
     offset = try getVal8(for: sourceArg)
     // skip after we get the val to ensure that we've incremented the PC
     // if an immediate value was accessed.
     guard passCondition == true else { return }
     } else {
     // there was no condition so the targetArg is the offset
     offset = try getVal8(for: targetArg)
     }
 */
    // Return from subroutine
    func ret(argTypes: (ArgType, ArgType)) throws {
        let conditionArg = argTypes.0
        
        // Check if we have a condition and the condition is satisfied.
        if let passCondition = checkCondition(for: conditionArg) {
            guard passCondition == true else { return }
        }
        
        // Read the two bytes at the address pointed to by the SP
        let retAddress = try getVal16(for: .SPptr)

        // FIXME: Additional checking for stack pointer overflow?
        SP = SP &+ 2

        PC = retAddress
    }
    
    func reti() throws {
        ei()
        try ret(argTypes: (.noReg, .noReg))
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

    
    // Rotate register right.
    // [0] -> [7 -> 0] -> C
    func rrc(argTypes: (ArgType, ArgType)) throws {
        
        let regVal = try getVal8(for: argTypes.0)
        let carry = (regVal & 0x01) == 0x01
        try set(val: (regVal >> 1) | (carry ? 0x80 : 0x00), for: argTypes.0)

        F.C = carry
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
    
    func rst(argTypes: (ArgType, ArgType)) throws {
        let vector = try getVal8(for: argTypes.0)
        
        // push the PC (which is now pointing to the instruction after the RST) onto the stack.
        SP = SP &- 2
        try set(val: PC, for: .SPptr)
        
        // go to the vector
        PC = UInt16(vector)
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

    // Set the bit value in in the target argument in the byte referenced in the source argument to 1.
    func set(argTypes: (ArgType, ArgType)) throws {
        let bitToSet = try getVal8(for: argTypes.0)
        let regVal = try getVal8(for: argTypes.1)
        let result = regVal | (1 << bitToSet)
        try set(val: result, for: argTypes.1)
        
        // Flags unaffected
    }

    /*
     argTypes: (ArgType, ArgType)) throws     func rl(argTypes: (ArgType, ArgType)) throws {
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

 */
    // Shift left arithmetic (shifts in 0 from right) register.
    // C <- [7 <- 0] <- 0
    func sla(argTypes: (ArgType, ArgType)) throws {
        let regVal = try getVal8(for: argTypes.0)
        let carry = (regVal >> 7) == 0x01
        let result = regVal << 1
        try set(val: result, for: argTypes.0)
        
        F.C = carry
        F.N = false
        F.H = false
        F.Z = (result == 0x00)
    }

    // Shift right arithmetic (copies msb) register.
    // [7] -> [7 -> 0] -> C
    func sra(argTypes: (ArgType, ArgType)) throws {
        let regVal = try getVal8(for: argTypes.0)
        let carry = (regVal & 0x01) == 0x01
        let result = (regVal & 0x80) | (regVal >> 1)
        try set(val: result, for: argTypes.0)
        
        F.C = carry
        F.N = false
        F.H = false
        F.Z = (result == 0x00)
    }
    
    // Shift right logic register.
    // 0 -> [7 -> 0] -> C
    func srl(argTypes: (ArgType, ArgType)) throws {
        let regVal = try getVal8(for: argTypes.0)
        let carry = (regVal & 0x01) == 0x01
        let result = regVal >> 1
        try set(val: result, for: argTypes.0)
        
        F.C = carry
        F.N = false
        F.H = false
        F.Z = (result == 0x00)
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
    
    // Swap places of least significant four bits with the most significant bits.
    func swap(argTypes: (ArgType, ArgType)) throws {
        let regVal = try getVal8(for: argTypes.0)
        let result = (regVal >> 4) | (regVal << 4)
        try set(val: result, for: argTypes.0)
        
        F.C = false
        F.N = false
        F.H = false
        F.Z = (result == 0x00)

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
