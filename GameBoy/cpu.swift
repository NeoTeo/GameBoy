//
//  cpu.swift
//  GameBoy
//
//  Created by Teo Sartori on 22/10/2016.
//  Copyright © 2016 Matteo Sartori. All rights reserved.
//

import Foundation

/*
     LR35902 CPU
 
 Registers.
 7                   0 7                  0
 +--------------------+-------------------+
 |         A          |         F         |
 +--------------------+-------------------+
 |         B          |         C         |
 +--------------------+-------------------+
 |         D          |         E         |
 +--------------------+-------------------+
 |         H          |         L         |
 +--------------------+-------------------+
 15                                       0
 +--------------------+-------------------+
 |        PC          |        SP         |
 +--------------------+-------------------+
 */
class CPU {
    
    /// registers
    var A: UInt8 = 0
    var B: UInt8 = 0
    var C: UInt8 = 0
    var D: UInt8 = 0
    var E: UInt8 = 0
    
    var H: UInt8 = 0
    var L: UInt8 = 0

    var PC: UInt16 = 0      // Program Counter
    var SP: UInt16 = 0      // Stack Pointer
    
    struct FlagRegister {
        init(rawValue: UInt8, Z: Bool = false, N: Bool = false, H: Bool = false, C: Bool = false) {
            self.rawValue = rawValue
        }
        
        var rawValue: UInt8 {
            get {
                // build an UInt8 from the flags
                var rawVal: UInt8 = 0
                if Z { rawVal |= (1 << 7) }
                if N { rawVal |= (1 << 6) }
                if H { rawVal |= (1 << 5) }
                if C { rawVal |= (1 << 4) }
                return rawVal
            }
            
            set {
                Z = ((newValue >> 7) & 1) == 1
                N = ((newValue >> 6) & 1) == 1
                H = ((newValue >> 5) & 1) == 1
                C = ((newValue >> 4) & 1) == 1
            }
        }
        
        var Z: Bool = false
        var N: Bool = false
        var H: Bool = false
        var C: Bool = false
    }

    var F = FlagRegister(rawValue: 0x00)

    var AF: UInt16 {
        get { return (UInt16(A) << 8) | UInt16(F.rawValue) }
        set {
            F = FlagRegister(rawValue: UInt8(newValue & 0xFF))
            A = UInt8(newValue >> 8)
        }
    }
    
    var BC: UInt16 {
        get { return (UInt16(B) << 8) | UInt16(C) }
        set {
            C = UInt8(newValue & 0xFF)
            B = UInt8(newValue >> 8)
        }
    }
    
    var DE: UInt16 {
        get { return (UInt16(D) << 8) | UInt16(E) }
        set {
            E = UInt8(newValue & 0xFF)
            D = UInt8(newValue >> 8)
        }
    }
    
    var HL: UInt16 {
        get { return (UInt16(H) << 8) | UInt16(L) }
        set {
            L = UInt8(newValue & 0xFF)
            H = UInt8(newValue >> 8)
        }
    }
    
    var ram: MEMORY!
    var subOpCycles: UInt8 = 1
    
    enum OpType {
        case adc8_8
        case add8_8
        case add16_16
        case and
        case cp
        case inc8
        case inc16
        case dec8
        case dec16
        case ld8_8
        case ld16_16
        case halt
        case nop
        case or
        case rlca
        case sbc
        case stop
        case sub
        case xor
        
        // cb prefix
        case rlc
    }
    
    enum RegisterType {
        case A
        case B
        case C
        case D
        case E
        case H
        case L
        case BC
        case DE
        case HL
        case SP
        
        case BCptr
        case DEptr
        case HLptr
        case HLptrInc
        case HLptrDec
        
        case i8
        case i8ptr
        case i16
        case i16ptr
        
        case noReg
    }

    // An op consists of an instruction id, a tuple of argument ids and a cycle count.
    // FIXME: Make this into an array and add all the ops as part of its definition.
    var ops =  [UInt8 : (OpType, (RegisterType, RegisterType), UInt8)]()
    
    func reset() {
        // Set initial register values as in DMG/GB
        AF = 0x01B0
        BC = 0x0013
        DE = 0x00D8
        HL = 0x014D
        SP = 0xFFFE
        PC = 0x0000
    
        // Move this to definition of ops
        ops[0x00] = (.nop, (.noReg, .noReg), 4)
        ops[0x01] = (.ld16_16, (.BC, .i16), 12)
        ops[0x02] = (.ld8_8, (.BCptr, .A), 8)
        ops[0x03] = (.inc16, (.BC, .noReg), 8)
        ops[0x04] = (.inc8, (.B, .noReg), 4)
        ops[0x05] = (.dec8, (.B, .noReg), 4)
        ops[0x06] = (.ld8_8, (.B, .i8), 8)
        ops[0x07] = (.rlca, (.noReg, .noReg), 4) // not to confuse with RLC A of the CB prefix instructions
        ops[0x08] = (.ld16_16, (.i16ptr, .SP), 20) // Usage: 1 opcode + 2 immediate = 3 bytes
        ops[0x09] = (.add16_16, (.HL, .BC), 8)
        ops[0x10] = (.stop, (.noReg, .noReg), 4)
        ops[0x0A] = (.ld8_8, (.A, .BCptr), 8)
        ops[0x0B] = (.dec16, (.BC, .noReg), 8)
        ops[0x0C] = (.inc8, (.C, .noReg), 4)
        ops[0x0D] = (.dec8, (.C, .noReg), 4)
        ops[0x0E] = (.ld8_8, (.C, .i8), 8)
        ops[0x12] = (.ld8_8, (.DEptr, .A), 8)
        ops[0x13] = (.inc16, (.DE, .noReg), 8)
        ops[0x14] = (.inc8, (.D, .noReg), 4)
        ops[0x15] = (.dec8, (.D, .noReg), 4)
        ops[0x16] = (.ld8_8, (.D, .i8), 8)
        ops[0x19] = (.add16_16, (.HL, .DE), 8)
        ops[0x1A] = (.ld8_8, (.A, .DEptr), 8)
        ops[0x1B] = (.dec16, (.DE, .noReg), 8)
        ops[0x1C] = (.inc8, (.E, .noReg), 4)
        ops[0x1D] = (.dec8, (.E, .noReg), 4)
        ops[0x1E] = (.ld8_8, (.E, .i8), 8)
        ops[0x22] = (.ld8_8, (.HLptrInc, .A), 8)
        ops[0x23] = (.inc16, (.HL, .noReg), 8)
        ops[0x24] = (.inc8, (.H, .noReg), 4)
        ops[0x25] = (.dec8, (.H, .noReg), 4)
        ops[0x26] = (.ld8_8, (.H, .i8), 8)
        ops[0x29] = (.add16_16, (.HL, .HL), 8)
        ops[0x2A] = (.ld8_8, (.A, .HLptrInc), 8)
        ops[0x2B] = (.dec16, (.HL, .noReg), 8)
        ops[0x2C] = (.inc8, (.L, .noReg), 4)
        ops[0x2D] = (.dec8, (.L, .noReg), 4)
        ops[0x2E] = (.ld8_8, (.L, .i8), 8)
        ops[0x32] = (.ld8_8, (.HLptrDec, .A), 8)
        ops[0x33] = (.inc16, (.SP, .noReg), 8)
        ops[0x34] = (.inc8, (.HLptr, .noReg), 12)
        ops[0x35] = (.dec8, (.HLptr, .noReg), 12)
        ops[0x36] = (.ld8_8, (.HLptr, .i8), 12)
        ops[0x39] = (.add16_16, (.HL, .SP), 8)
        ops[0x3A] = (.ld8_8, (.A, .HLptrDec), 8)
        ops[0x3B] = (.dec16, (.SP, .noReg), 8)
        ops[0x3C] = (.inc8, (.A, .noReg), 4)
        ops[0x3D] = (.dec8, (.A, .noReg), 4)
        ops[0x3E] = (.ld8_8, (.A, .i8), 8)
        
        ops[0x40] = (.ld8_8, (.B, .B), 4) // ??
        ops[0x41] = (.ld8_8, (.B, .C), 4)
        ops[0x42] = (.ld8_8, (.B, .D), 4)
        ops[0x43] = (.ld8_8, (.B, .E), 4)
        ops[0x44] = (.ld8_8, (.B, .H), 4)
        ops[0x45] = (.ld8_8, (.B, .L), 4)
        ops[0x46] = (.ld8_8, (.B, .HLptr), 8)
        ops[0x47] = (.ld8_8, (.B, .A), 4)
        
        ops[0x48] = (.ld8_8, (.C, .B), 4)
        ops[0x49] = (.ld8_8, (.C, .C), 4) // ??
        ops[0x4A] = (.ld8_8, (.C, .D), 4)
        ops[0x4B] = (.ld8_8, (.C, .E), 4)
        ops[0x4C] = (.ld8_8, (.C, .H), 4)
        ops[0x4D] = (.ld8_8, (.C, .L), 4)
        ops[0x4E] = (.ld8_8, (.C, .HLptr), 8)
        ops[0x4F] = (.ld8_8, (.C, .A), 4)
        
        ops[0x50] = (.ld8_8, (.D, .B), 4)
        ops[0x51] = (.ld8_8, (.D, .C), 4)
        ops[0x52] = (.ld8_8, (.D, .D), 4) // ??
        ops[0x53] = (.ld8_8, (.D, .E), 4)
        ops[0x54] = (.ld8_8, (.D, .H), 4)
        ops[0x55] = (.ld8_8, (.D, .L), 4)
        ops[0x56] = (.ld8_8, (.D, .HLptr), 8)
        ops[0x57] = (.ld8_8, (.D, .A), 4)
        
        ops[0x58] = (.ld8_8, (.E, .B), 4)
        ops[0x59] = (.ld8_8, (.E, .C), 4)
        ops[0x5A] = (.ld8_8, (.E, .D), 4)
        ops[0x5B] = (.ld8_8, (.E, .E), 4) // ??
        ops[0x5C] = (.ld8_8, (.E, .H), 4)
        ops[0x5D] = (.ld8_8, (.E, .L), 4)
        ops[0x5E] = (.ld8_8, (.E, .HLptr), 8)
        ops[0x5F] = (.ld8_8, (.E, .A), 4)

        ops[0x60] = (.ld8_8, (.H, .B), 4)
        ops[0x61] = (.ld8_8, (.H, .C), 4)
        ops[0x62] = (.ld8_8, (.H, .D), 4)
        ops[0x63] = (.ld8_8, (.H, .E), 4)
        ops[0x64] = (.ld8_8, (.H, .H), 4) // ??
        ops[0x65] = (.ld8_8, (.H, .L), 4)
        ops[0x66] = (.ld8_8, (.H, .HLptr), 8)
        ops[0x67] = (.ld8_8, (.H, .A), 4)
        
        ops[0x68] = (.ld8_8, (.L, .B), 4)
        ops[0x69] = (.ld8_8, (.L, .C), 4)
        ops[0x6A] = (.ld8_8, (.L, .D), 4)
        ops[0x6B] = (.ld8_8, (.L, .E), 4)
        ops[0x6C] = (.ld8_8, (.L, .H), 4)
        ops[0x6D] = (.ld8_8, (.L, .L), 4) // ??
        ops[0x6E] = (.ld8_8, (.L, .HLptr), 8)
        ops[0x6F] = (.ld8_8, (.L, .A), 4)
        
        ops[0x70] = (.ld8_8, (.HLptr, .B), 8)
        ops[0x71] = (.ld8_8, (.HLptr, .C), 8)
        ops[0x72] = (.ld8_8, (.HLptr, .D), 8)
        ops[0x73] = (.ld8_8, (.HLptr, .E), 8)
        ops[0x74] = (.ld8_8, (.HLptr, .H), 8)
        ops[0x75] = (.ld8_8, (.HLptr, .L), 8)
        ops[0x76] = (.halt, (.noReg, .noReg), 4) // not properly implemented
        ops[0x77] = (.ld8_8, (.HLptr, .A), 8)
        
        ops[0x78] = (.ld8_8, (.A, .B), 4)
        ops[0x79] = (.ld8_8, (.A, .C), 4)
        ops[0x7A] = (.ld8_8, (.A, .D), 4)
        ops[0x7B] = (.ld8_8, (.A, .E), 4)
        ops[0x7C] = (.ld8_8, (.A, .H), 4)
        ops[0x7D] = (.ld8_8, (.A, .L), 4)
        ops[0x7E] = (.ld8_8, (.A, .HLptr), 8)
        ops[0x7F] = (.ld8_8, (.A, .A), 4) // ??
        
        ops[0x80] = (.add8_8, (.A, .B), 4)
        ops[0x81] = (.add8_8, (.A, .C), 4)
        ops[0x82] = (.add8_8, (.A, .D), 4)
        ops[0x83] = (.add8_8, (.A, .E), 4)
        ops[0x84] = (.add8_8, (.A, .H), 4)
        ops[0x85] = (.add8_8, (.A, .L), 4)
        ops[0x86] = (.add8_8, (.A, .HLptr), 8)
        ops[0x87] = (.add8_8, (.A, .A), 4)
        
        ops[0x88] = (.adc8_8, (.A, .B), 4)
        ops[0x89] = (.adc8_8, (.A, .C), 4)
        ops[0x8A] = (.adc8_8, (.A, .D), 4)
        ops[0x8B] = (.adc8_8, (.A, .E), 4)
        ops[0x8C] = (.adc8_8, (.A, .H), 4)
        ops[0x8D] = (.adc8_8, (.A, .L), 4)
        ops[0x8E] = (.adc8_8, (.A, .HLptr), 8)
        ops[0x8F] = (.adc8_8, (.A, .A), 4)
        
        ops[0x90] = (.sub, (.A, .B), 4)
        ops[0x91] = (.sub, (.A, .C), 4)
        ops[0x92] = (.sub, (.A, .D), 4)
        ops[0x93] = (.sub, (.A, .E), 4)
        ops[0x94] = (.sub, (.A, .H), 4)
        ops[0x95] = (.sub, (.A, .L), 4)
        ops[0x96] = (.sub, (.A, .HLptr), 8)
        ops[0x97] = (.sub, (.A, .A), 4)
        
        ops[0x98] = (.sbc, (.A, .B), 4)
        ops[0x99] = (.sbc, (.A, .C), 4)
        ops[0x9A] = (.sbc, (.A, .D), 4)
        ops[0x9B] = (.sbc, (.A, .E), 4)
        ops[0x9C] = (.sbc, (.A, .H), 4)
        ops[0x9D] = (.sbc, (.A, .L), 4)
        ops[0x9E] = (.sbc, (.A, .HLptr), 8)
        ops[0x9F] = (.sbc, (.A, .A), 4)

        ops[0xA0] = (.and, (.A, .B), 4)
        ops[0xA1] = (.and, (.A, .C), 4)
        ops[0xA2] = (.and, (.A, .D), 4)
        ops[0xA3] = (.and, (.A, .E), 4)
        ops[0xA4] = (.and, (.A, .H), 4)
        ops[0xA5] = (.and, (.A, .L), 4)
        ops[0xA6] = (.and, (.A, .HLptr), 8)
        ops[0xA7] = (.and, (.A, .A), 4)

        ops[0xA8] = (.xor, (.A, .B), 4)
        ops[0xA9] = (.xor, (.A, .C), 4)
        ops[0xAA] = (.xor, (.A, .D), 4)
        ops[0xAB] = (.xor, (.A, .E), 4)
        ops[0xAC] = (.xor, (.A, .H), 4)
        ops[0xAD] = (.xor, (.A, .L), 4)
        ops[0xAE] = (.xor, (.A, .HLptr), 8)
        ops[0xAF] = (.xor, (.A, .A), 4)
        
        ops[0xB0] = (.or, (.A, .B), 4)
        ops[0xB1] = (.or, (.A, .C), 4)
        ops[0xB2] = (.or, (.A, .D), 4)
        ops[0xB3] = (.or, (.A, .E), 4)
        ops[0xB4] = (.or, (.A, .H), 4)
        ops[0xB5] = (.or, (.A, .L), 4)
        ops[0xB6] = (.or, (.A, .HLptr), 8)
        ops[0xB7] = (.or, (.A, .A), 4)

        ops[0xB8] = (.cp, (.A, .B), 4)
        ops[0xB9] = (.cp, (.A, .C), 4)
        ops[0xBA] = (.cp, (.A, .D), 4)
        ops[0xBB] = (.cp, (.A, .E), 4)
        ops[0xBC] = (.cp, (.A, .H), 4)
        ops[0xBD] = (.cp, (.A, .L), 4)
        ops[0xBE] = (.cp, (.A, .HLptr), 8)
        ops[0xBF] = (.cp, (.A, .A), 4)

        
        ops[0xCE] = (.adc8_8, (.A, .i8), 8)
        ops[0xD6] = (.sub, (.A, .i8), 8)
    }

    
    enum CPUError : Error {
        case UnknownRegister
        case RegisterReadFailure
        case RegisterWriteFailure
    }
    

    func clockTick() {
        subOpCycles -= 1
        if subOpCycles > 0 {  return }

        /// Read from ram
        let opcode = read8(at: PC)

        print("PC is \(PC)")
        print("opcode is 0x" + String(format: "%2X",opcode) )

        guard let (op, args, cycles) = ops[opcode] else {
            print("ERROR reading from ops table")
            return
        }
        // TODO: Consider using the functions directly in the table instead since they
        // all take args anyway
        subOpCycles = cycles
        do {
            switch op {
            case .adc8_8:
                try adc(argTypes: args)
            case .add8_8:
                try add8_8(argTypes: args)
            case .add16_16:
                try add16_16(argTypes: args)
            case .and:
                try and(argTypes: args)
            case .cp:
                try cp(argTypes: args)
            case .ld8_8:
                try ld8_8(argTypes: args)
            case .ld16_16:
                try ld16_16(argTypes: args)
            case .dec8:
                try dec8(argType: args.0)
            case .dec16:
                try dec16(argType: args.0)
            case .halt:
                halt()
            case .inc8:
                try inc8(argType: args.0)
            case .inc16:
                try inc16(argType: args.0)
            case .nop:
                break
            case .or:
                try or(argTypes: args)
            case .rlca:
                try rlca()
            case .sbc:
                try sbc(argTypes: args)
            case .stop:
                stop()
            case .sub:
                try sub8_8(argTypes: args)
            case .xor:
                try xor(argTypes: args)
            // CB prefix
            case .rlc:
                try rlc(argType: args.0)
            }
        } catch {
            print("Error executing opcodes \(error) \(op)")
        }
    }
}
