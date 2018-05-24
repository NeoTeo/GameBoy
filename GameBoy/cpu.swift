//
//  cpu.swift
//  GameBoy
//
//  Created by Teo Sartori on 22/10/2016.
//  Copyright © 2016 Matteo Sartori. All rights reserved.
//

import Foundation

protocol MEMORY {
    
    init(size: UInt16)
    func read8(at location: UInt16) -> UInt8
    func read16(at location: UInt16) -> UInt16
    mutating func write(at location: UInt16, with value: UInt8)
    
    // Helper function - might be useful for DMA
    func insert(data: [UInt8], at address: UInt16)
}

protocol SYSTEM {
    var cpu: CPU { get }
    var ram: MEMORY { get }
    
    func start(clockRate: Int)
}

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
        case nop
        case inc8
        case inc16
        case dec8
        case dec16
//        case ld8_8
        case ld8_16
//        case ld16_8
        case ld16_16
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
        case HLptr
        
        case i8
        case i16
        
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
        ops[0x34] = (.inc8, (.HLptr, .noReg), 12)
        ops[0x35] = (.dec8, (.HLptr, .noReg), 12)
        ops[0x3C] = (.inc8, (.A, .noReg), 4)
        ops[0x04] = (.inc8, (.B, .noReg), 4)
        ops[0x3D] = (.dec8, (.A, .noReg), 4)
    }

    
    enum CPUError : Error {
        case UnknownRegister
        case RegisterReadFailure
        case RegisterWriteFailure
    }
    
    func getVal8(for register: RegisterType) throws -> UInt8 {
        switch register {
            case .A: return A
            case .B: return B
            case .C: return C
            case .D: return D
            case .E: return E
            case .H: return H
            case .L: return L
            default: throw CPUError.UnknownRegister
        }
    }
    
    func set(val: UInt8, for register: RegisterType) throws {
        switch register {
        case .A: A = val
        case .B: B = val
        case .C: C = val
        case .D: D = val
        case .E: E = val
        case .H: H = val
        case .L: L = val
        default: throw CPUError.UnknownRegister
        }
    }
    
    func getVal16(for register: RegisterType) throws -> UInt16 {
        switch register {
            case .BC: return BC
            case .DE: return DE
            case .HL: return HL
            case .SP: return SP
            default: throw CPUError.UnknownRegister
        }
    }
    
    func set(val: UInt16, for register: RegisterType) throws {
        switch register {
        case .BC: BC = val
        case .DE: DE = val
        case .HL: HL = val
        case .SP: SP = val
        default: throw CPUError.UnknownRegister
        }
    }
    
    func clockTick() {
        subOpCycles -= 1
        if subOpCycles > 0 {  return }

        /// Read from ram
        let opcode = ram.read8(at: PC)
        incPc()

        print("PC is \(PC)")
        print("opcode is 0x" + String(format: "%2X",opcode) )

        guard let (op, args, cycles) = ops[opcode] else {
            print("ERROR reading from ops table")
            return
        }
        
        subOpCycles = cycles
        do {
            switch op {
            case .nop:
                subOpCycles = 4
            case .ld16_16:
                try ld16_16(argTypes: args)
            case .ld8_16:
                try ld8_16(argTypes: args)
            case .dec8:
                try dec8(argType: args.0)
            case .dec16:
                try dec16(argType: args.0)
            case .inc8:
                try inc8(argType: args.0)
            case .inc16:
                try inc16(argType: args.0)
            }
        } catch {
            print("Error executing opcodes \(error)")
        }
    }
    
//    func clockTick() {
//
//        subOpCycles -= 1
//        if subOpCycles > 0 {  return }
//
//        /// Read from ram
//        let opcode = ram.read8(at: PC)
//        incPc()
//
//        print("PC is \(PC)")
//        print("opcode is 0x" + String(format: "%2X",opcode) )
//
//        /** interpret data/instruction
//         Each opcode can affect the registers, the RAM and the interrupts
//         **/
//        switch opcode {
//        case 0x00:  /// NOP
//            subOpCycles = 4
//
//            // Make LD,INC, etc. functions that takes various args so we can look
//            // them up in a table instead of this switch or at least reduce its size.
//        case 0x01:  /// LD BC, d16
//            BC = ram.read16(at: PC)
//            incPc()
//            incPc()
//            subOpCycles = 12
//
//        case 0x02:  /// LD (BC), A, load location at BC with register A
//            ram.write(at: BC, with: A)
//            subOpCycles = 8
//
//        case 0x03:  /// INC BC
//            inc(nn: &BC)
//            subOpCycles = 8
//
//        case 0x04:  /// INC B
//            inc(n: &B)
//            subOpCycles = 4
//
//        case 0x05:  /// DEC B
//            B -= 1
//            subOpCycles = 4
//
//        case 0x06:  /// LD B, d8
//            B = ram.read8(at: PC)
//            subOpCycles = 8
//
//        // LD SP, d16
//        case 0x31:
//            SP = ram.read16(at: PC)
//            incPc()
//            incPc()
//            subOpCycles = 12
//
//        case 0x3C:
//            inc(n: &A) // INC A
//            subOpCycles = 4
//
//        case 0x3D:
//            dec(n: &A)
//            subOpCycles = 4
//
//        default:
//            subOpCycles = 4
//            break
//        }
//    }
    
}

// Extension defining instructions
extension CPU {
    func incPc(_ bytes: UInt16=1) {
        PC = (PC &+ bytes)
    }
    
    // LD n, nn
    // Put value nn into n
    // Flags unaffected.
    func ld16_16(argTypes: (RegisterType, RegisterType)) throws {
        var nn: UInt16
        let source = argTypes.1
        let target = argTypes.0
        
        if source == .i16 {
            nn = ram.read16(at: PC)
            incPc(2)
        } else {
            nn = try getVal16(for: source)
        }
        
        try set(val: nn, for: target)
    }
    
    // LD A,
    func ld8_16(argTypes: (RegisterType, RegisterType)) throws {
        
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
            n = ram.read8(at: addr)
            n = n &+ 1
            ram.write(at: addr, with: n)
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
            n = ram.read8(at: addr)
            n = n &- 1
            ram.write(at: addr, with: n)

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
}

class RAM : MEMORY {

    let size: UInt16// in bytes
    var ram: [UInt8]
    
    required init(size: UInt16) {
        self.size = size
        ram = Array(repeating: 0, count: Int(size))
    }
    
    func read16(at location: UInt16) -> UInt16 {
        let msb = ram[Int(location)]
        let lsb = ram[Int(location+1)]
        return (UInt16(msb) << 8) | UInt16(lsb)
    }
    
    func read8(at location: UInt16) -> UInt8 {
        return ram[Int(location)]
    }
    
    // FIXME: Add some checks for writing to illegal addresses. 
    func write(at location: UInt16, with value: UInt8) {
        ram[Int(location)] = value
    }

    // Helper functions
    func insert(data: [UInt8], at address: UInt16) {
        ram.insert(contentsOf: data, at: Int(address))
        
    }
}

class Gameboy : SYSTEM {
    
    var cpu: CPU
    var ram: MEMORY
    
    init() {
        
        cpu = CPU()
        ram = RAM(size: 0xFFFF)
        // Connect the cpu with the memory
        cpu.ram = ram
        cpu.reset()
    }
    
    func start(clockRate: Int) {
        
        let interval = TimeInterval( 1 / clockRate )
        let clockTimer = Timer(timeInterval: interval, repeats: true, block: runCycle)
        
        // bodge some code into ram
        bodgeBootLoader()
        
        RunLoop.current.add(clockTimer, forMode: .defaultRunLoopMode)
    }
    
    func runCycle(timer: Timer) {
        cpu.clockTick()
    }
    
    func bodgeBootLoader() {
        let binaryName = "DMG_ROM.bin"
        guard let path = Bundle.main.path(forResource: binaryName, ofType: nil),
            let bootBinary = try? loadBinary(from: URL(fileURLWithPath: path))
        else {
            print("Failed to load boot binary.")
            return
        }
        
        ram.insert(data: bootBinary, at: 0x0000)
    }
}
