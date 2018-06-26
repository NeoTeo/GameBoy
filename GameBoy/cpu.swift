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
    
    var IME: Bool = false   // Interrupt Master Enable
    
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


    var mmu: MMU!
    var timer: Timer!
    
    var subOpCycles: UInt8 = 1
    
    enum OpType {
        case adc8_8
        case add8_8
        case add16_16
        case and
        case call
        case cb
        case ccf
        case cp
        case cpl
        case daa
        case di
        case ei
        case inc8
        case inc16
        case jp
        case jr
        case dec8
        case dec16
        case ld8_8
        case ld16_16
        case halt
        case nop
        case or
        case pop
        case push
        case ret
        case reti
        case rlca
        case rla
        case rr
        case rra
        case rrca
        case rst
        case sbc
        case scf
        case stop
        case sub
        case xor
    }
    
    enum CbOpType {
        // cb prefix
        case bit
        case res
        case rlc
        case rrc
        case rl
        case rr
        case set
        case sla
        case srl
        case sra
        case swap
    }
    
    enum ArgType {
        case A
        case B
        case C
        case D
        case E
        case H
        case L
        case AF
        case BC
        case DE
        case HL
        case SP
        
        case BCptr
        case DEptr
        case HLptr
        case SPptr
        case HLptrInc
        case HLptrDec
        
        case HiRamC
        case HiRamI8
        
        case i8
        case i8ptr
        case i16
        case i16ptr
        
        case noReg
        
        // condition codes
        case Zero        // Execute if Z is set
        case NotZero     // Execute if Z is not set
        case Carry       // Execute if C is set
        case NoCarry     // Execute if C is not set

        // An unsigned 3bit value ranging from 0 to 7
        case u3_0
        case u3_1
        case u3_2
        case u3_3
        case u3_4
        case u3_5
        case u3_6
        case u3_7
//        case u3(UInt8)   // An unsigned 3bit value ranging from 0 to 7
        // Wanted to do this with associated values but equality becomes an arse pain.
        // Because ArgType contains cases with associated values Swift will not
        // automatically synthesize the equality operator. So we'll have to do it.
        
        // I could embed the ArgType into an Arg enum that could either be an
        // ArgType or an ArgVal and thus just use scalar directly when appropriate.
        // The cost is added complexity which I'd rather avoid. This, although
        // more verbose, is also clearer to read.
//        static func ==(lhs: ArgType, rhs: ArgType) -> Bool {
//            switch (lhs, rhs) {
//            case let (.u3(a), .u3(b)):
//                return a == b
//            default:
//                return lhs == rhs
//            }
//        }
        
        // Restart vectors
        case vec00h
        case vec08h
        case vec10h
        case vec18h
        case vec20h
        case vec28h
        case vec30h
        case vec38h
        
        // Interrupt vectors
        case vec40h  // vblank
        case vec48h  // LCD status
        case vec50h  // timer
        case vec58h  // serial
        case vec60h  // joypad
    }

    // An op consists of an instruction id, a tuple of argument ids, a cycle count
    // and a byte count.
    // FIXME: Make this into an array and add all the ops as part of its definition.
    var ops =  [UInt8 : (OpType, (ArgType, ArgType), UInt8, UInt8)]()
    var cbOps = [UInt8 : (CbOpType, (ArgType, ArgType), UInt8)]()
    var systemClock: Double
    let maxClock: Double = 4_194_304
    init(sysClock: Double) {
        systemClock = sysClock
    }
    
    func reset() {
        // Set initial register values as in DMG/GB
        AF = 0x0000 //0x01B0
        BC = 0x0000 //0x0013
        DE = 0x0000 //0x00D8
        HL = 0x0000 //0x014D
        SP = 0x0000 //0xFFFE
        PC = 0x0000
        
//        timer.setClock(hertz: 60)
//        timer.start {
//            // For now fake a vsync
////            mmu.IF = self.setFlag(for: DmgMmu.InterruptFlag.vblank.rawValue , in: mmu.IF)
//            self.mmu.setIF(flag: .vblank)
//        }
    
        // Move this to definition of ops
        ops[0x00] = (.nop, (.noReg, .noReg), 4, 1)
        ops[0x01] = (.ld16_16, (.BC, .i16), 12, 3)
        ops[0x02] = (.ld8_8, (.BCptr, .A), 8, 1)
        ops[0x03] = (.inc16, (.BC, .noReg), 8, 1)
        ops[0x04] = (.inc8, (.B, .noReg), 4, 1)
        ops[0x05] = (.dec8, (.B, .noReg), 4, 1)
        ops[0x06] = (.ld8_8, (.B, .i8), 8, 2)
        ops[0x07] = (.rlca, (.noReg, .noReg), 4, 1) // not to confuse with RLC A of the CB prefix instructions
        ops[0x08] = (.ld16_16, (.i16ptr, .SP), 20, 3) // Usage: 1 opcode + 2 immediate = 3 bytes
        ops[0x09] = (.add16_16, (.HL, .BC), 8, 1)
        ops[0x0A] = (.ld8_8, (.A, .BCptr), 8, 1)
        ops[0x0B] = (.dec16, (.BC, .noReg), 8, 1)
        ops[0x0C] = (.inc8, (.C, .noReg), 4, 1)
        ops[0x0D] = (.dec8, (.C, .noReg), 4, 1)
        ops[0x0E] = (.ld8_8, (.C, .i8), 8, 2)
        ops[0x0F] = (.rrca, (.noReg, .noReg), 4, 1)
        
        ops[0x10] = (.stop, (.noReg, .noReg), 4, 2)
        ops[0x11] = (.ld16_16, (.DE, .i16), 12, 3)
        ops[0x12] = (.ld8_8, (.DEptr, .A), 8, 1)
        ops[0x13] = (.inc16, (.DE, .noReg), 8, 1)
        ops[0x14] = (.inc8, (.D, .noReg), 4, 1)
        ops[0x15] = (.dec8, (.D, .noReg), 4, 1)
        ops[0x16] = (.ld8_8, (.D, .i8), 8, 2)
        ops[0x17] = (.rla, (.noReg, .noReg), 4, 1)
        ops[0x18] = (.jr, (.noReg, .i8), 12, 2)
        ops[0x19] = (.add16_16, (.HL, .DE), 8, 1)
        ops[0x1A] = (.ld8_8, (.A, .DEptr), 8, 1)
        ops[0x1B] = (.dec16, (.DE, .noReg), 8, 1)
        ops[0x1C] = (.inc8, (.E, .noReg), 4, 1)
        ops[0x1D] = (.dec8, (.E, .noReg), 4, 1)
        ops[0x1E] = (.ld8_8, (.E, .i8), 8, 2)
        ops[0x1F] = (.rra, (.noReg, .noReg), 4, 1)
        
        ops[0x20] = (.jr, (.NotZero, .i8), 12, 2)
        ops[0x21] = (.ld16_16, (.HL, .i16), 12, 3)
        ops[0x22] = (.ld8_8, (.HLptrInc, .A), 8, 1)
        ops[0x23] = (.inc16, (.HL, .noReg), 8, 1)
        ops[0x24] = (.inc8, (.H, .noReg), 4, 1)
        ops[0x25] = (.dec8, (.H, .noReg), 4, 1)
        ops[0x26] = (.ld8_8, (.H, .i8), 8, 2)
        ops[0x27] = (.daa, (.noReg, .noReg), 4, 1)
        ops[0x28] = (.jr, (.Zero, .i8), 12, 2)
        ops[0x29] = (.add16_16, (.HL, .HL), 8, 1)
        ops[0x2A] = (.ld8_8, (.A, .HLptrInc), 8, 1)
        ops[0x2B] = (.dec16, (.HL, .noReg), 8, 1)
        ops[0x2C] = (.inc8, (.L, .noReg), 4, 1)
        ops[0x2D] = (.dec8, (.L, .noReg), 4, 1)
        ops[0x2E] = (.ld8_8, (.L, .i8), 8, 2)
        ops[0x2F] = (.cpl, (.noReg, .noReg), 4, 1)
        
        ops[0x30] = (.jr, (.NoCarry, .i8), 12, 2)
        ops[0x31] = (.ld16_16, (.SP, .i16), 12, 3)
        ops[0x32] = (.ld8_8, (.HLptrDec, .A), 8, 1)
        ops[0x33] = (.inc16, (.SP, .noReg), 8, 1)
        ops[0x34] = (.inc8, (.HLptr, .noReg), 12, 1)
        ops[0x35] = (.dec8, (.HLptr, .noReg), 12, 1)
        ops[0x36] = (.ld8_8, (.HLptr, .i8), 12, 1)
        ops[0x37] = (.scf, (.noReg, .noReg), 4, 1)
        ops[0x38] = (.jr, (.Carry, .i8), 12, 2)
        ops[0x39] = (.add16_16, (.HL, .SP), 8, 1)
        ops[0x3A] = (.ld8_8, (.A, .HLptrDec), 8, 1)
        ops[0x3B] = (.dec16, (.SP, .noReg), 8, 1)
        ops[0x3C] = (.inc8, (.A, .noReg), 4, 1)
        ops[0x3D] = (.dec8, (.A, .noReg), 4, 1)
        ops[0x3E] = (.ld8_8, (.A, .i8), 8, 2)
        ops[0x3F] = (.ccf, (.noReg, .noReg), 4, 1)
        
        ops[0x40] = (.ld8_8, (.B, .B), 4, 1) // ??
        ops[0x41] = (.ld8_8, (.B, .C), 4, 1)
        ops[0x42] = (.ld8_8, (.B, .D), 4, 1)
        ops[0x43] = (.ld8_8, (.B, .E), 4, 1)
        ops[0x44] = (.ld8_8, (.B, .H), 4, 1)
        ops[0x45] = (.ld8_8, (.B, .L), 4, 1)
        ops[0x46] = (.ld8_8, (.B, .HLptr), 8, 1)
        ops[0x47] = (.ld8_8, (.B, .A), 4, 1)
        
        ops[0x48] = (.ld8_8, (.C, .B), 4, 1)
        ops[0x49] = (.ld8_8, (.C, .C), 4, 1) // ??
        ops[0x4A] = (.ld8_8, (.C, .D), 4, 1)
        ops[0x4B] = (.ld8_8, (.C, .E), 4, 1)
        ops[0x4C] = (.ld8_8, (.C, .H), 4, 1)
        ops[0x4D] = (.ld8_8, (.C, .L), 4, 1)
        ops[0x4E] = (.ld8_8, (.C, .HLptr), 8, 1)
        ops[0x4F] = (.ld8_8, (.C, .A), 4, 1)
        
        ops[0x50] = (.ld8_8, (.D, .B), 4, 1)
        ops[0x51] = (.ld8_8, (.D, .C), 4, 1)
        ops[0x52] = (.ld8_8, (.D, .D), 4, 1) // ??
        ops[0x53] = (.ld8_8, (.D, .E), 4, 1)
        ops[0x54] = (.ld8_8, (.D, .H), 4, 1)
        ops[0x55] = (.ld8_8, (.D, .L), 4, 1)
        ops[0x56] = (.ld8_8, (.D, .HLptr), 8, 1)
        ops[0x57] = (.ld8_8, (.D, .A), 4, 1)
        
        ops[0x58] = (.ld8_8, (.E, .B), 4, 1)
        ops[0x59] = (.ld8_8, (.E, .C), 4, 1)
        ops[0x5A] = (.ld8_8, (.E, .D), 4, 1)
        ops[0x5B] = (.ld8_8, (.E, .E), 4, 1) // ??
        ops[0x5C] = (.ld8_8, (.E, .H), 4, 1)
        ops[0x5D] = (.ld8_8, (.E, .L), 4, 1)
        ops[0x5E] = (.ld8_8, (.E, .HLptr), 8, 1)
        ops[0x5F] = (.ld8_8, (.E, .A), 4, 1)

        ops[0x60] = (.ld8_8, (.H, .B), 4, 1)
        ops[0x61] = (.ld8_8, (.H, .C), 4, 1)
        ops[0x62] = (.ld8_8, (.H, .D), 4, 1)
        ops[0x63] = (.ld8_8, (.H, .E), 4, 1)
        ops[0x64] = (.ld8_8, (.H, .H), 4, 1) // ??
        ops[0x65] = (.ld8_8, (.H, .L), 4, 1)
        ops[0x66] = (.ld8_8, (.H, .HLptr), 8, 1)
        ops[0x67] = (.ld8_8, (.H, .A), 4, 1)
        
        ops[0x68] = (.ld8_8, (.L, .B), 4, 1)
        ops[0x69] = (.ld8_8, (.L, .C), 4, 1)
        ops[0x6A] = (.ld8_8, (.L, .D), 4, 1)
        ops[0x6B] = (.ld8_8, (.L, .E), 4, 1)
        ops[0x6C] = (.ld8_8, (.L, .H), 4, 1)
        ops[0x6D] = (.ld8_8, (.L, .L), 4, 1) // ??
        ops[0x6E] = (.ld8_8, (.L, .HLptr), 8, 1)
        ops[0x6F] = (.ld8_8, (.L, .A), 4, 1)
        
        ops[0x70] = (.ld8_8, (.HLptr, .B), 8, 1)
        ops[0x71] = (.ld8_8, (.HLptr, .C), 8, 1)
        ops[0x72] = (.ld8_8, (.HLptr, .D), 8, 1)
        ops[0x73] = (.ld8_8, (.HLptr, .E), 8, 1)
        ops[0x74] = (.ld8_8, (.HLptr, .H), 8, 1)
        ops[0x75] = (.ld8_8, (.HLptr, .L), 8, 1)
        ops[0x76] = (.halt, (.noReg, .noReg), 4, 1) // not properly implemented
        ops[0x77] = (.ld8_8, (.HLptr, .A), 8, 1)
        
        ops[0x78] = (.ld8_8, (.A, .B), 4, 1)
        ops[0x79] = (.ld8_8, (.A, .C), 4, 1)
        ops[0x7A] = (.ld8_8, (.A, .D), 4, 1)
        ops[0x7B] = (.ld8_8, (.A, .E), 4, 1)
        ops[0x7C] = (.ld8_8, (.A, .H), 4, 1)
        ops[0x7D] = (.ld8_8, (.A, .L), 4, 1)
        ops[0x7E] = (.ld8_8, (.A, .HLptr), 8, 1)
        ops[0x7F] = (.ld8_8, (.A, .A), 4, 1) // ??
        
        ops[0x80] = (.add8_8, (.A, .B), 4, 1)
        ops[0x81] = (.add8_8, (.A, .C), 4, 1)
        ops[0x82] = (.add8_8, (.A, .D), 4, 1)
        ops[0x83] = (.add8_8, (.A, .E), 4, 1)
        ops[0x84] = (.add8_8, (.A, .H), 4, 1)
        ops[0x85] = (.add8_8, (.A, .L), 4, 1)
        ops[0x86] = (.add8_8, (.A, .HLptr), 8, 1)
        ops[0x87] = (.add8_8, (.A, .A), 4, 1)
        
        ops[0x88] = (.adc8_8, (.A, .B), 4, 1)
        ops[0x89] = (.adc8_8, (.A, .C), 4, 1)
        ops[0x8A] = (.adc8_8, (.A, .D), 4, 1)
        ops[0x8B] = (.adc8_8, (.A, .E), 4, 1)
        ops[0x8C] = (.adc8_8, (.A, .H), 4, 1)
        ops[0x8D] = (.adc8_8, (.A, .L), 4, 1)
        ops[0x8E] = (.adc8_8, (.A, .HLptr), 8, 1)
        ops[0x8F] = (.adc8_8, (.A, .A), 4, 1)
        
        ops[0x90] = (.sub, (.A, .B), 4, 1)
        ops[0x91] = (.sub, (.A, .C), 4, 1)
        ops[0x92] = (.sub, (.A, .D), 4, 1)
        ops[0x93] = (.sub, (.A, .E), 4, 1)
        ops[0x94] = (.sub, (.A, .H), 4, 1)
        ops[0x95] = (.sub, (.A, .L), 4, 1)
        ops[0x96] = (.sub, (.A, .HLptr), 8, 1)
        ops[0x97] = (.sub, (.A, .A), 4, 1)
        
        ops[0x98] = (.sbc, (.A, .B), 4, 1)
        ops[0x99] = (.sbc, (.A, .C), 4, 1)
        ops[0x9A] = (.sbc, (.A, .D), 4, 1)
        ops[0x9B] = (.sbc, (.A, .E), 4, 1)
        ops[0x9C] = (.sbc, (.A, .H), 4, 1)
        ops[0x9D] = (.sbc, (.A, .L), 4, 1)
        ops[0x9E] = (.sbc, (.A, .HLptr), 8, 1)
        ops[0x9F] = (.sbc, (.A, .A), 4, 1)

        ops[0xA0] = (.and, (.A, .B), 4, 1)
        ops[0xA1] = (.and, (.A, .C), 4, 1)
        ops[0xA2] = (.and, (.A, .D), 4, 1)
        ops[0xA3] = (.and, (.A, .E), 4, 1)
        ops[0xA4] = (.and, (.A, .H), 4, 1)
        ops[0xA5] = (.and, (.A, .L), 4, 1)
        ops[0xA6] = (.and, (.A, .HLptr), 8, 1)
        ops[0xA7] = (.and, (.A, .A), 4, 1)

        ops[0xA8] = (.xor, (.A, .B), 4, 1)
        ops[0xA9] = (.xor, (.A, .C), 4, 1)
        ops[0xAA] = (.xor, (.A, .D), 4, 1)
        ops[0xAB] = (.xor, (.A, .E), 4, 1)
        ops[0xAC] = (.xor, (.A, .H), 4, 1)
        ops[0xAD] = (.xor, (.A, .L), 4, 1)
        ops[0xAE] = (.xor, (.A, .HLptr), 8, 1)
        ops[0xAF] = (.xor, (.A, .A), 4, 1)
        
        ops[0xB0] = (.or, (.A, .B), 4, 1)
        ops[0xB1] = (.or, (.A, .C), 4, 1)
        ops[0xB2] = (.or, (.A, .D), 4, 1)
        ops[0xB3] = (.or, (.A, .E), 4, 1)
        ops[0xB4] = (.or, (.A, .H), 4, 1)
        ops[0xB5] = (.or, (.A, .L), 4, 1)
        ops[0xB6] = (.or, (.A, .HLptr), 8, 1)
        ops[0xB7] = (.or, (.A, .A), 4, 1)

        ops[0xB8] = (.cp, (.A, .B), 4, 1)
        ops[0xB9] = (.cp, (.A, .C), 4, 1)
        ops[0xBA] = (.cp, (.A, .D), 4, 1)
        ops[0xBB] = (.cp, (.A, .E), 4, 1)
        ops[0xBC] = (.cp, (.A, .H), 4, 1)
        ops[0xBD] = (.cp, (.A, .L), 4, 1)
        ops[0xBE] = (.cp, (.A, .HLptr), 8, 1)
        ops[0xBF] = (.cp, (.A, .A), 4, 1)

        ops[0xC0] = (.ret, (.NotZero, .noReg), 20, 1)
        ops[0xC1] = (.pop, (.BC, .noReg), 12, 1)
        ops[0xC2] = (.jp, (.NotZero, .i16), 16, 3)
        ops[0xC3] = (.jp, (.noReg, .i16), 16, 3)
        ops[0xC4] = (.call, (.NotZero, .i16), 24, 3)
        ops[0xC5] = (.push, (.noReg, .BC), 16, 1)
        ops[0xC7] = (.rst, (.vec00h, .noReg), 16, 1)
        ops[0xC8] = (.ret, (.Zero, .noReg), 20, 1)
        ops[0xC9] = (.ret, (.noReg, .noReg), 16, 1)
        ops[0xCA] = (.jp, (.Zero, .i16), 16, 3)
        ops[0xCB] = (.cb, (.noReg, .noReg), 4, 1)
        ops[0xCC] = (.call, (.Zero, .i16), 24, 3)
        ops[0xCD] = (.call, (.noReg, .i16), 24, 3)
        ops[0xCE] = (.adc8_8, (.A, .i8), 8, 2)
        ops[0xCF] = (.rst, (.vec08h, .noReg), 16, 1)
        
        ops[0xD0] = (.ret, (.NoCarry, .noReg), 20, 1)
        ops[0xD1] = (.pop, (.DE, .noReg), 12, 1)
        ops[0xD2] = (.jp, (.NoCarry, .i16), 16, 3)
        ops[0xD4] = (.call, (.NoCarry, .i16), 24, 3)
        ops[0xD5] = (.push, (.noReg, .DE), 16, 1)
        ops[0xD6] = (.sub, (.A, .i8), 8, 2)
        ops[0xD7] = (.rst, (.vec10h, .noReg), 16, 1)
        ops[0xD8] = (.ret, (.Carry, .noReg), 20, 1)
        ops[0xD9] = (.reti, (.noReg, .noReg), 16, 1)
        ops[0xDA] = (.jp, (.Carry, .i16), 16, 3)
        ops[0xDC] = (.call, (.Carry, .i16), 24, 3)
        ops[0xDE] = (.sbc, (.A, .i8), 8, 2)
        ops[0xDF] = (.rst, (.vec18h, .noReg), 16, 1)

        ops[0xE0] = (.ld8_8, (.HiRamI8, .A), 12, 2)
        ops[0xE1] = (.pop, (.HL, .noReg), 12, 1)
        ops[0xE2] = (.ld8_8, (.HiRamC, .A), 8, 2)
        ops[0xE5] = (.push, (.noReg, .HL), 16, 1)
        ops[0xE7] = (.rst, (.vec20h, .noReg), 16, 1)
        ops[0xE9] = (.jp, (.noReg, .HLptr), 4, 1)
        ops[0xEA] = (.ld8_8, (.i16ptr, .A), 16, 3)
        ops[0xEE] = (.xor, (.i8, .noReg), 8, 2)
        ops[0xEF] = (.rst, (.vec28h, .noReg), 16, 1)
        
        ops[0xF0] = (.ld8_8, (.A, .HiRamI8), 12, 2)
        ops[0xF1] = (.pop, (.AF, .noReg), 12, 1)
        ops[0xF2] = (.ld8_8, (.A, .HiRamC), 8, 2)
        ops[0xF3] = (.di, (.noReg, .noReg), 4, 1)
        ops[0xF5] = (.push, (.noReg, .AF), 16, 1)
        ops[0xD7] = (.rst, (.vec30h, .noReg), 16, 1)
        ops[0xFA] = (.ld8_8, (.A, .i16ptr), 16, 3)
        ops[0xFB] = (.ei, (.noReg, .noReg), 4, 1)
        ops[0xFE] = (.cp, (.A, .i8), 8, 1)
        ops[0xFF] = (.rst, (.vec38h, .noReg), 16, 1)

        // -------------------------- change to array when complete
        
        // CB prefix operations
        cbOps[0x00] = (.rlc, (.B, .noReg), 8)
        cbOps[0x01] = (.rlc, (.C, .noReg), 8)
        cbOps[0x02] = (.rlc, (.D, .noReg), 8)
        cbOps[0x03] = (.rlc, (.E, .noReg), 8)
        cbOps[0x04] = (.rlc, (.H, .noReg), 8)
        cbOps[0x05] = (.rlc, (.L, .noReg), 8)
        cbOps[0x06] = (.rlc, (.HLptr, .noReg), 16)
        cbOps[0x07] = (.rlc, (.A, .noReg), 8)

        cbOps[0x08] = (.rrc, (.B, .noReg), 8)
        cbOps[0x09] = (.rrc, (.C, .noReg), 8)
        cbOps[0x0A] = (.rrc, (.D, .noReg), 8)
        cbOps[0x0B] = (.rrc, (.E, .noReg), 8)
        cbOps[0x0C] = (.rrc, (.H, .noReg), 8)
        cbOps[0x0D] = (.rrc, (.L, .noReg), 8)
        cbOps[0x0E] = (.rrc, (.HLptr, .noReg), 16)
        cbOps[0x0F] = (.rrc, (.A, .noReg), 8)

        cbOps[0x10] = (.rl, (.B, .noReg), 8)
        cbOps[0x11] = (.rl, (.C, .noReg), 8)
        cbOps[0x12] = (.rl, (.D, .noReg), 8)
        cbOps[0x13] = (.rl, (.E, .noReg), 8)
        cbOps[0x14] = (.rl, (.H, .noReg), 8)
        cbOps[0x15] = (.rl, (.L, .noReg), 8)
        cbOps[0x16] = (.rl, (.HLptr, .noReg), 16)
        cbOps[0x17] = (.rl, (.A, .noReg), 8)
        
        cbOps[0x18] = (.rr, (.B, .noReg), 8)
        cbOps[0x19] = (.rr, (.C, .noReg), 8)
        cbOps[0x1A] = (.rr, (.D, .noReg), 8)
        cbOps[0x1B] = (.rr, (.E, .noReg), 8)
        cbOps[0x1C] = (.rr, (.H, .noReg), 8)
        cbOps[0x1D] = (.rr, (.L, .noReg), 8)
        cbOps[0x1E] = (.rr, (.HLptr, .noReg), 16)
        cbOps[0x1F] = (.rr, (.A, .noReg), 8)

        cbOps[0x20] = (.sla, (.B, .noReg), 8)
        cbOps[0x21] = (.sla, (.C, .noReg), 8)
        cbOps[0x22] = (.sla, (.D, .noReg), 8)
        cbOps[0x23] = (.sla, (.E, .noReg), 8)
        cbOps[0x24] = (.sla, (.H, .noReg), 8)
        cbOps[0x25] = (.sla, (.L, .noReg), 8)
        cbOps[0x26] = (.sla, (.HLptr, .noReg), 16)
        cbOps[0x27] = (.sla, (.A, .noReg), 8)
        
        cbOps[0x28] = (.sra, (.B, .noReg), 8)
        cbOps[0x29] = (.sra, (.C, .noReg), 8)
        cbOps[0x2A] = (.sra, (.D, .noReg), 8)
        cbOps[0x2B] = (.sra, (.E, .noReg), 8)
        cbOps[0x2C] = (.sra, (.H, .noReg), 8)
        cbOps[0x2D] = (.sra, (.L, .noReg), 8)
        cbOps[0x2E] = (.sra, (.HLptr, .noReg), 16)
        cbOps[0x2F] = (.sra, (.A, .noReg), 8)

        cbOps[0x30] = (.swap, (.B, .noReg), 8)
        cbOps[0x31] = (.swap, (.C, .noReg), 8)
        cbOps[0x32] = (.swap, (.D, .noReg), 8)
        cbOps[0x33] = (.swap, (.E, .noReg), 8)
        cbOps[0x34] = (.swap, (.H, .noReg), 8)
        cbOps[0x35] = (.swap, (.L, .noReg), 8)
        cbOps[0x36] = (.swap, (.HLptr, .noReg), 16)
        cbOps[0x37] = (.swap, (.A, .noReg), 8)
        
        cbOps[0x38] = (.srl, (.B, .noReg), 8)
        cbOps[0x39] = (.srl, (.C, .noReg), 8)
        cbOps[0x3A] = (.srl, (.D, .noReg), 8)
        cbOps[0x3B] = (.srl, (.E, .noReg), 8)
        cbOps[0x3C] = (.srl, (.H, .noReg), 8)
        cbOps[0x3D] = (.srl, (.L, .noReg), 8)
        cbOps[0x3E] = (.srl, (.HLptr, .noReg), 16)
        cbOps[0x3F] = (.srl, (.A, .noReg), 8)

        cbOps[0x40] = (.bit, (.u3_0, .B), 8)
        cbOps[0x41] = (.bit, (.u3_0, .C), 8)
        cbOps[0x42] = (.bit, (.u3_0, .D), 8)
        cbOps[0x43] = (.bit, (.u3_0, .E), 8)
        cbOps[0x44] = (.bit, (.u3_0, .H), 8)
        cbOps[0x45] = (.bit, (.u3_0, .L), 8)
        cbOps[0x46] = (.bit, (.u3_0, .HLptr), 12)
        cbOps[0x47] = (.bit, (.u3_0, .A), 8)
        
        cbOps[0x48] = (.bit, (.u3_1, .B), 8)
        cbOps[0x49] = (.bit, (.u3_1, .C), 8)
        cbOps[0x4A] = (.bit, (.u3_1, .D), 8)
        cbOps[0x4B] = (.bit, (.u3_1, .E), 8)
        cbOps[0x4C] = (.bit, (.u3_1, .H), 8)
        cbOps[0x4D] = (.bit, (.u3_1, .L), 8)
        cbOps[0x4E] = (.bit, (.u3_1, .HLptr), 12)
        cbOps[0x4F] = (.bit, (.u3_1, .A), 8)

        cbOps[0x50] = (.bit, (.u3_2, .B), 8)
        cbOps[0x51] = (.bit, (.u3_2, .C), 8)
        cbOps[0x52] = (.bit, (.u3_2, .D), 8)
        cbOps[0x53] = (.bit, (.u3_2, .E), 8)
        cbOps[0x54] = (.bit, (.u3_2, .H), 8)
        cbOps[0x55] = (.bit, (.u3_2, .L), 8)
        cbOps[0x56] = (.bit, (.u3_2, .HLptr), 12)
        cbOps[0x57] = (.bit, (.u3_2, .A), 8)
    
        cbOps[0x58] = (.bit, (.u3_3, .B), 8)
        cbOps[0x59] = (.bit, (.u3_3, .C), 8)
        cbOps[0x5A] = (.bit, (.u3_3, .D), 8)
        cbOps[0x5B] = (.bit, (.u3_3, .E), 8)
        cbOps[0x5C] = (.bit, (.u3_3, .H), 8)
        cbOps[0x5D] = (.bit, (.u3_3, .L), 8)
        cbOps[0x5E] = (.bit, (.u3_3, .HLptr), 12)
        cbOps[0x5F] = (.bit, (.u3_3, .A), 8)

        cbOps[0x60] = (.bit, (.u3_4, .B), 8)
        cbOps[0x61] = (.bit, (.u3_4, .C), 8)
        cbOps[0x62] = (.bit, (.u3_4, .D), 8)
        cbOps[0x63] = (.bit, (.u3_4, .E), 8)
        cbOps[0x64] = (.bit, (.u3_4, .H), 8)
        cbOps[0x65] = (.bit, (.u3_4, .L), 8)
        cbOps[0x66] = (.bit, (.u3_4, .HLptr), 12)
        cbOps[0x67] = (.bit, (.u3_4, .A), 8)
        
        cbOps[0x68] = (.bit, (.u3_5, .B), 8)
        cbOps[0x69] = (.bit, (.u3_5, .C), 8)
        cbOps[0x6A] = (.bit, (.u3_5, .D), 8)
        cbOps[0x6B] = (.bit, (.u3_5, .E), 8)
        cbOps[0x6C] = (.bit, (.u3_5, .H), 8)
        cbOps[0x6D] = (.bit, (.u3_5, .L), 8)
        cbOps[0x6E] = (.bit, (.u3_5, .HLptr), 12)
        cbOps[0x6F] = (.bit, (.u3_5, .A), 8)
        
        cbOps[0x70] = (.bit, (.u3_6, .B), 8)
        cbOps[0x71] = (.bit, (.u3_6, .C), 8)
        cbOps[0x72] = (.bit, (.u3_6, .D), 8)
        cbOps[0x73] = (.bit, (.u3_6, .E), 8)
        cbOps[0x74] = (.bit, (.u3_6, .H), 8)
        cbOps[0x75] = (.bit, (.u3_6, .L), 8)
        cbOps[0x76] = (.bit, (.u3_6, .HLptr), 12)
        cbOps[0x77] = (.bit, (.u3_6, .A), 8)
        
        cbOps[0x78] = (.bit, (.u3_7, .B), 8)
        cbOps[0x79] = (.bit, (.u3_7, .C), 8)
        cbOps[0x7A] = (.bit, (.u3_7, .D), 8)
        cbOps[0x7B] = (.bit, (.u3_7, .E), 8)
        cbOps[0x7C] = (.bit, (.u3_7, .H), 8)
        cbOps[0x7D] = (.bit, (.u3_7, .L), 8)
        cbOps[0x7E] = (.bit, (.u3_7, .HLptr), 12)
        cbOps[0x7F] = (.bit, (.u3_7, .A), 8)

        cbOps[0x80] = (.res, (.u3_0, .B), 8)
        cbOps[0x81] = (.res, (.u3_0, .C), 8)
        cbOps[0x82] = (.res, (.u3_0, .D), 8)
        cbOps[0x83] = (.res, (.u3_0, .E), 8)
        cbOps[0x84] = (.res, (.u3_0, .H), 8)
        cbOps[0x85] = (.res, (.u3_0, .L), 8)
        cbOps[0x86] = (.res, (.u3_0, .HLptr), 12)
        cbOps[0x87] = (.res, (.u3_0, .A), 8)
        
        cbOps[0x88] = (.res, (.u3_1, .B), 8)
        cbOps[0x89] = (.res, (.u3_1, .C), 8)
        cbOps[0x8A] = (.res, (.u3_1, .D), 8)
        cbOps[0x8B] = (.res, (.u3_1, .E), 8)
        cbOps[0x8C] = (.res, (.u3_1, .H), 8)
        cbOps[0x8D] = (.res, (.u3_1, .L), 8)
        cbOps[0x8E] = (.res, (.u3_1, .HLptr), 12)
        cbOps[0x8F] = (.res, (.u3_1, .A), 8)

        cbOps[0x90] = (.res, (.u3_2, .B), 8)
        cbOps[0x91] = (.res, (.u3_2, .C), 8)
        cbOps[0x92] = (.res, (.u3_2, .D), 8)
        cbOps[0x93] = (.res, (.u3_2, .E), 8)
        cbOps[0x94] = (.res, (.u3_2, .H), 8)
        cbOps[0x95] = (.res, (.u3_2, .L), 8)
        cbOps[0x96] = (.res, (.u3_2, .HLptr), 12)
        cbOps[0x97] = (.res, (.u3_2, .A), 8)
        
        cbOps[0x98] = (.res, (.u3_3, .B), 8)
        cbOps[0x99] = (.res, (.u3_3, .C), 8)
        cbOps[0x9A] = (.res, (.u3_3, .D), 8)
        cbOps[0x9B] = (.res, (.u3_3, .E), 8)
        cbOps[0x9C] = (.res, (.u3_3, .H), 8)
        cbOps[0x9D] = (.res, (.u3_3, .L), 8)
        cbOps[0x9E] = (.res, (.u3_3, .HLptr), 12)
        cbOps[0x9F] = (.res, (.u3_3, .A), 8)
        
        cbOps[0xA0] = (.res, (.u3_4, .B), 8)
        cbOps[0xA1] = (.res, (.u3_4, .C), 8)
        cbOps[0xA2] = (.res, (.u3_4, .D), 8)
        cbOps[0xA3] = (.res, (.u3_4, .E), 8)
        cbOps[0xA4] = (.res, (.u3_4, .H), 8)
        cbOps[0xA5] = (.res, (.u3_4, .L), 8)
        cbOps[0xA6] = (.res, (.u3_4, .HLptr), 12)
        cbOps[0xA7] = (.res, (.u3_4, .A), 8)
        
        cbOps[0xA8] = (.res, (.u3_5, .B), 8)
        cbOps[0xA9] = (.res, (.u3_5, .C), 8)
        cbOps[0xAA] = (.res, (.u3_5, .D), 8)
        cbOps[0xAB] = (.res, (.u3_5, .E), 8)
        cbOps[0xAC] = (.res, (.u3_5, .H), 8)
        cbOps[0xAD] = (.res, (.u3_5, .L), 8)
        cbOps[0xAE] = (.res, (.u3_5, .HLptr), 12)
        cbOps[0xAF] = (.res, (.u3_5, .A), 8)
        
        cbOps[0xB0] = (.res, (.u3_6, .B), 8)
        cbOps[0xB1] = (.res, (.u3_6, .C), 8)
        cbOps[0xB2] = (.res, (.u3_6, .D), 8)
        cbOps[0xB3] = (.res, (.u3_6, .E), 8)
        cbOps[0xB4] = (.res, (.u3_6, .H), 8)
        cbOps[0xB5] = (.res, (.u3_6, .L), 8)
        cbOps[0xB6] = (.res, (.u3_6, .HLptr), 12)
        cbOps[0xB7] = (.res, (.u3_6, .A), 8)
        
        cbOps[0xB8] = (.res, (.u3_7, .B), 8)
        cbOps[0xB9] = (.res, (.u3_7, .C), 8)
        cbOps[0xBA] = (.res, (.u3_7, .D), 8)
        cbOps[0xBB] = (.res, (.u3_7, .E), 8)
        cbOps[0xBC] = (.res, (.u3_7, .H), 8)
        cbOps[0xBD] = (.res, (.u3_7, .L), 8)
        cbOps[0xBE] = (.res, (.u3_7, .HLptr), 12)
        cbOps[0xBF] = (.res, (.u3_7, .A), 8)

        cbOps[0xC0] = (.set, (.u3_0, .B), 8)
        cbOps[0xC1] = (.set, (.u3_0, .C), 8)
        cbOps[0xC2] = (.set, (.u3_0, .D), 8)
        cbOps[0xC3] = (.set, (.u3_0, .E), 8)
        cbOps[0xC4] = (.set, (.u3_0, .H), 8)
        cbOps[0xC5] = (.set, (.u3_0, .L), 8)
        cbOps[0xC6] = (.set, (.u3_0, .HLptr), 12)
        cbOps[0xC7] = (.set, (.u3_0, .A), 8)
        
        cbOps[0xC8] = (.set, (.u3_1, .B), 8)
        cbOps[0xC9] = (.set, (.u3_1, .C), 8)
        cbOps[0xCA] = (.set, (.u3_1, .D), 8)
        cbOps[0xCB] = (.set, (.u3_1, .E), 8)
        cbOps[0xCC] = (.set, (.u3_1, .H), 8)
        cbOps[0xCD] = (.set, (.u3_1, .L), 8)
        cbOps[0xCE] = (.set, (.u3_1, .HLptr), 12)
        cbOps[0xCF] = (.set, (.u3_1, .A), 8)
        
        cbOps[0xD0] = (.set, (.u3_2, .B), 8)
        cbOps[0xD1] = (.set, (.u3_2, .C), 8)
        cbOps[0xD2] = (.set, (.u3_2, .D), 8)
        cbOps[0xD3] = (.set, (.u3_2, .E), 8)
        cbOps[0xD4] = (.set, (.u3_2, .H), 8)
        cbOps[0xD5] = (.set, (.u3_2, .L), 8)
        cbOps[0xD6] = (.set, (.u3_2, .HLptr), 12)
        cbOps[0xD7] = (.set, (.u3_2, .A), 8)
        
        cbOps[0xD8] = (.set, (.u3_3, .B), 8)
        cbOps[0xD9] = (.set, (.u3_3, .C), 8)
        cbOps[0xDA] = (.set, (.u3_3, .D), 8)
        cbOps[0xDB] = (.set, (.u3_3, .E), 8)
        cbOps[0xDC] = (.set, (.u3_3, .H), 8)
        cbOps[0xDD] = (.set, (.u3_3, .L), 8)
        cbOps[0xDE] = (.set, (.u3_3, .HLptr), 12)
        cbOps[0xDF] = (.set, (.u3_3, .A), 8)
        
        cbOps[0xE0] = (.set, (.u3_4, .B), 8)
        cbOps[0xE1] = (.set, (.u3_4, .C), 8)
        cbOps[0xE2] = (.set, (.u3_4, .D), 8)
        cbOps[0xE3] = (.set, (.u3_4, .E), 8)
        cbOps[0xE4] = (.set, (.u3_4, .H), 8)
        cbOps[0xE5] = (.set, (.u3_4, .L), 8)
        cbOps[0xE6] = (.set, (.u3_4, .HLptr), 12)
        cbOps[0xE7] = (.set, (.u3_4, .A), 8)
        
        cbOps[0xE8] = (.set, (.u3_5, .B), 8)
        cbOps[0xE9] = (.set, (.u3_5, .C), 8)
        cbOps[0xEA] = (.set, (.u3_5, .D), 8)
        cbOps[0xEB] = (.set, (.u3_5, .E), 8)
        cbOps[0xEC] = (.set, (.u3_5, .H), 8)
        cbOps[0xED] = (.set, (.u3_5, .L), 8)
        cbOps[0xEE] = (.set, (.u3_5, .HLptr), 12)
        cbOps[0xEF] = (.set, (.u3_5, .A), 8)
        
        cbOps[0xF0] = (.set, (.u3_6, .B), 8)
        cbOps[0xF1] = (.set, (.u3_6, .C), 8)
        cbOps[0xF2] = (.set, (.u3_6, .D), 8)
        cbOps[0xF3] = (.set, (.u3_6, .E), 8)
        cbOps[0xF4] = (.set, (.u3_6, .H), 8)
        cbOps[0xF5] = (.set, (.u3_6, .L), 8)
        cbOps[0xF6] = (.set, (.u3_6, .HLptr), 12)
        cbOps[0xF7] = (.set, (.u3_6, .A), 8)
        
        cbOps[0xF8] = (.set, (.u3_7, .B), 8)
        cbOps[0xF9] = (.set, (.u3_7, .C), 8)
        cbOps[0xFA] = (.set, (.u3_7, .D), 8)
        cbOps[0xFB] = (.set, (.u3_7, .E), 8)
        cbOps[0xFC] = (.set, (.u3_7, .H), 8)
        cbOps[0xFD] = (.set, (.u3_7, .L), 8)
        cbOps[0xFE] = (.set, (.u3_7, .HLptr), 12)
        cbOps[0xFF] = (.set, (.u3_7, .A), 8)

    }

    
    enum CPUError : Error {
        case UnknownRegister
        case RegisterReadFailure
        case RegisterWriteFailure
        case RamError
    }
    
    var cbMode = false

//    var prevTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    
    func clockTick() {
        
        subOpCycles -= 1
        if subOpCycles > 0 {  return }

        var dbgPr = false
        
        // Never reaches 6A because we don't have a v-blank yet
//        if PC == 0x86 {
        if PC == 0xFE {
            print("PC is \(String(format: "%2X",PC))")
            dbgPr = true
        }
        
        /// Read from ram.
        guard let opcode = try? read8(at: PC, incPC: true) else {
            print("clockTick failed to read opcode.")
            return
        }
        
        // We may have to do some checking on the PC
        // https://realboyemulator.wordpress.com/2013/01/18/emulating-the-core-2/
        
        if dbgPr == true {
            print("opcode is 0x" + String(format: "%2X",opcode) )
            print("CB prefix is \(cbMode)")
            print("HL: \(HL)")
        }

        if cbMode == true {
            handleCbOps(opcode: opcode) }
        else {
            handleOps(opcode: opcode)
        }
        
        interruptHandler()
    }

    func interruptHandler() {
        // Check for interrupts
        if (IME == true) && (mmu.IE != 0) && (mmu.IF != 0) {
            
            // Immediately disable interrupts
            IME = false
            
            //            let interrupt = DmgMmu.InterruptFlag(rawValue: mmu.IE & mmu.IF)!
            let interrupts = mmu.IE & mmu.IF
            var vector: ArgType = .noReg
            
            // Execute by priority.
            for i in 0 ..< 5 {
                if ((interrupts >> i) & 0x1) == 0x1 {
                    // Mask out the triggered interrupt
                    let interrupt = interrupts & (1 << i)
                    
                    // Clear the flag
                    mmu.IF = clear(bit: interrupt, in: mmu.IF)
                    
                    let int = mmuInterruptFlag(rawValue: interrupt)!
                    switch int {
                    case .vblank: vector = .vec40h
                    case .lcdStat: vector = .vec48h
                    case .timer: vector = .vec50h
                    case .serial: vector = .vec58h
                    case .joypad: vector = .vec60h
                    }
                    
                    try! rst(argTypes: (vector, .noReg))
                    
                    // Only one interrupt gets executed unless IME has been re-enabled
                    // by the interrupt code.
                    if IME == false { break }
                }
            }
        }
    }
    
    func handleOps(opcode: UInt8) {
        
        guard let (op, args, cycles, bytes) = ops[opcode] else {
            print("ERROR reading from ops table for opcode \(opcode)")
            return
        }
                
        // FIXME: Bodge until I get each instruction to return the cycles it uses.
        // In the meantime this ensures that the cycles, currently defined at 4MHz,
        // get scaled appropriately. Eg. if system clock is 1_048_576 then a 12 cycle op
        // will count as 12 * (1_048_576 / 4_194_304) = 3 cycles
        subOpCycles = UInt8(Double(cycles) * (systemClock / maxClock))
        
        // TODO: Consider using the functions directly in the op-table instead since they
        // all take args anyway
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
            case .call:
                try call(argTypes: args)
            case .cb:
                cbMode = true
            case .ccf:
                ccf()
            case .cp:
                try cp(argTypes: args)
            case .cpl:
                cpl()
            case .daa:
                daa()
            case .dec8:
                try dec8(argType: args.0)
            case .dec16:
                try dec16(argType: args.0)
            case .di:
                di()
            case .ei:
                ei()
            case .halt:
                halt()
            case .inc8:
                try inc8(argType: args.0)
            case .inc16:
                try inc16(argType: args.0)
            case .jp: try jp(argTypes: args)
            case .jr: try jr(argTypes: args)
            case .ld8_8:
                try ld8_8(argTypes: args)
            case .ld16_16:
                try ld16_16(argTypes: args)
            case .nop:
                break
            case .or:
                try or(argTypes: args)
            case .pop:
                try pop(argTypes: args)
            case .push:
                try push(argTypes: args)
            case .ret:
                try ret(argTypes: args)
            case .reti:
                try reti()
            case .rlca:
                try rlca()
            case .rla:
                try rla()
            case .rra:
                try rra()
            case .rrca:
                try rrca()
                //                print("operation \(op) not yet implemented")
                //                break
            case .rst: try rst(argTypes: args)
            case .sbc: try sbc(argTypes: args)
            case .scf: scf()
            case .stop: stop()
            case .sub: try sub8_8(argTypes: args)
            case .xor: try xor(argTypes: args)
            case .rr: try rr(argTypes: args)
            }
            
        } catch {
            print("Error executing opcodes \(error) \(op)")
        }

    }
    
    func handleCbOps(opcode: UInt8) {
        // CB prefix
        guard let (op, args, cycles) = cbOps[opcode] else {
            print("ERROR reading from CB ops table")
            return
        }
        
        // Always reset cbMode.
        cbMode = false
        
        // TODO: Consider using the functions directly in the table instead since they
        // all take args anyway
        subOpCycles = cycles
        do {
            switch op {
            case .bit:
                try bit(argTypes: args)
//                print("operation \(op) not yet implemented")
//                break

            case .rlc:
                try rlc(argType: args.0)
            case .rrc:
                try rrc(argTypes: args)
            case .rl:
                try rl(argTypes: args)
            case .rr:
                try rr(argTypes: args)
            case .res:
                try res(argTypes: args)
            case .set:
                try set(argTypes: args)
            case .sla:
                try sla(argTypes: args)
            case .srl:
                try srl(argTypes: args)
            case .sra:
                try sra(argTypes: args)
            case .swap:
                try swap(argTypes: args)
            }
        } catch {
            print("Error executing opcodes \(error) \(op)")
        }
    }
}
