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
    //func insert(data: [UInt8], at address: UInt16)
    func replace(data: [UInt8], from address: UInt16) throws
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
        case ld8_8
        case ld8_16
        case ld16_8
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
        ops[0x02] = (.ld16_8, (.BCptr, .A), 8)
        ops[0x03] = (.inc16, (.BC, .noReg), 8)
        ops[0x04] = (.inc8, (.B, .noReg), 4)
        ops[0x05] = (.dec8, (.B, .noReg), 4)
        ops[0x06] = (.ld8_8, (.B, .i8), 8)
        ops[0x08] = (.ld16_16, (.i16ptr, .SP), 20) // Usage: 1 opcode + 2 immediate = 3 bytes
        ops[0x0A] = (.ld8_16, (.A, .BCptr), 8)
        ops[0x0B] = (.dec16, (.BC, .noReg), 8)
        ops[0x0C] = (.inc8, (.C, .noReg), 4)
        ops[0x0D] = (.dec8, (.C, .noReg), 4)
        ops[0x0E] = (.ld8_8, (.C, .i8), 8)
        ops[0x12] = (.ld16_8, (.DEptr, .A), 8)
        ops[0x13] = (.inc16, (.DE, .noReg), 8)
        ops[0x14] = (.inc8, (.D, .noReg), 4)
        ops[0x15] = (.dec8, (.D, .noReg), 4)
        ops[0x16] = (.ld8_8, (.D, .i8), 8)
        ops[0x1A] = (.ld8_16, (.A, .DEptr), 8)
        ops[0x1B] = (.dec16, (.DE, .noReg), 8)
        ops[0x1C] = (.inc8, (.E, .noReg), 4)
        ops[0x1D] = (.dec8, (.E, .noReg), 4)
        ops[0x1E] = (.ld8_8, (.E, .i8), 8)
        ops[0x22] = (.ld16_8, (.HLptrInc, .A), 8)
        ops[0x23] = (.inc16, (.HL, .noReg), 8)
        ops[0x24] = (.inc8, (.H, .noReg), 4)
        ops[0x25] = (.dec8, (.H, .noReg), 4)
        ops[0x26] = (.ld8_8, (.H, .i8), 8)
        ops[0x2A] = (.ld8_16, (.A, .HLptrInc), 8)
        ops[0x2B] = (.dec16, (.HL, .noReg), 8)
        ops[0x2C] = (.inc8, (.L, .noReg), 4)
        ops[0x2D] = (.dec8, (.L, .noReg), 4)
        ops[0x2E] = (.ld8_8, (.L, .i8), 8)
        ops[0x32] = (.ld16_8, (.HLptrDec, .A), 8)
        ops[0x33] = (.inc16, (.SP, .noReg), 8)
        ops[0x34] = (.inc8, (.HLptr, .noReg), 12)
        ops[0x35] = (.dec8, (.HLptr, .noReg), 12)
        ops[0x36] = (.ld16_8, (.HLptr, .i8), 12)
        ops[0x3A] = (.ld8_16, (.A, .HLptrDec), 8)
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
        ops[0x46] = (.ld8_16, (.B, .HLptr), 8)
        ops[0x47] = (.ld8_8, (.B, .A), 4)
        
        ops[0x48] = (.ld8_8, (.C, .B), 4)
        ops[0x49] = (.ld8_8, (.C, .C), 4) // ??
        ops[0x4A] = (.ld8_8, (.C, .D), 4)
        ops[0x4B] = (.ld8_8, (.C, .E), 4)
        ops[0x4C] = (.ld8_8, (.C, .H), 4)
        ops[0x4D] = (.ld8_8, (.C, .L), 4)
        ops[0x4E] = (.ld8_16, (.C, .HLptr), 8)
        ops[0x4F] = (.ld8_8, (.C, .A), 4)
        
        ops[0x50] = (.ld8_8, (.D, .B), 4)
        ops[0x51] = (.ld8_8, (.D, .C), 4)
        ops[0x52] = (.ld8_8, (.D, .D), 4) // ??
        ops[0x53] = (.ld8_8, (.D, .E), 4)
        ops[0x54] = (.ld8_8, (.D, .H), 4)
        ops[0x55] = (.ld8_8, (.D, .L), 4)
        ops[0x56] = (.ld8_16, (.D, .HLptr), 8)
        ops[0x57] = (.ld8_8, (.D, .A), 4)
        
        ops[0x58] = (.ld8_8, (.E, .B), 4)
        ops[0x59] = (.ld8_8, (.E, .C), 4)
        ops[0x5A] = (.ld8_8, (.E, .D), 4)
        ops[0x5B] = (.ld8_8, (.E, .E), 4) // ??
        ops[0x5C] = (.ld8_8, (.E, .H), 4)
        ops[0x5D] = (.ld8_8, (.E, .L), 4)
        ops[0x5E] = (.ld8_16, (.E, .HLptr), 8)
        ops[0x5F] = (.ld8_8, (.E, .A), 4)

        ops[0x60] = (.ld8_8, (.H, .B), 4)
        ops[0x61] = (.ld8_8, (.H, .C), 4)
        ops[0x62] = (.ld8_8, (.H, .D), 4)
        ops[0x63] = (.ld8_8, (.H, .E), 4)
        ops[0x64] = (.ld8_8, (.H, .H), 4) // ??
        ops[0x65] = (.ld8_8, (.H, .L), 4)
        ops[0x66] = (.ld8_16, (.H, .HLptr), 8)
        ops[0x67] = (.ld8_8, (.H, .A), 4)
        
        ops[0x68] = (.ld8_8, (.L, .B), 4)
        ops[0x69] = (.ld8_8, (.L, .C), 4)
        ops[0x6A] = (.ld8_8, (.L, .D), 4)
        ops[0x6B] = (.ld8_8, (.L, .E), 4)
        ops[0x6C] = (.ld8_8, (.L, .H), 4)
        ops[0x6D] = (.ld8_8, (.L, .L), 4) // ??
        ops[0x6E] = (.ld8_16, (.L, .HLptr), 8)
        ops[0x6F] = (.ld8_8, (.L, .A), 4)
        
        ops[0x70] = (.ld16_8, (.HLptr, .B), 8)
        ops[0x71] = (.ld16_8, (.HLptr, .C), 8)
        ops[0x72] = (.ld16_8, (.HLptr, .D), 8)
        ops[0x73] = (.ld16_8, (.HLptr, .E), 8)
        ops[0x74] = (.ld16_8, (.HLptr, .H), 8)
        ops[0x75] = (.ld16_8, (.HLptr, .L), 8)
        // ops[0x76] = (.halt, (.noReg, .noReg), 4) // not yet implemented
        ops[0x77] = (.ld16_8, (.HLptr, .A), 8)
        
        ops[0x78] = (.ld8_8, (.A, .B), 4)
        ops[0x79] = (.ld8_8, (.A, .C), 4)
        ops[0x7A] = (.ld8_8, (.A, .D), 4)
        ops[0x7B] = (.ld8_8, (.A, .E), 4)
        ops[0x7C] = (.ld8_8, (.A, .H), 4)
        ops[0x7D] = (.ld8_8, (.A, .L), 4)
        ops[0x7E] = (.ld8_16, (.A, .HLptr), 8)
        ops[0x7F] = (.ld8_8, (.A, .A), 4) // ??
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
            
        case .i8: return read8(at: PC)
        
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
            
        // Write value to memory pointed to by the given register
        case .BCptr: write(at: BC, with: val)
        case .DEptr: write(at: DE, with: val)
        case .HLptr: write(at: HL, with: val)
            
        case .HLptrInc: write(at: HL, with: val) ; try inc16(argType: .HL)
        case .HLptrDec: write(at: HL, with: val) ; try dec16(argType: .HL)
            
        case .i8: write(at: PC, with: val)
            
        default: throw CPUError.UnknownRegister
        }
    }
    
    func getVal16(for register: RegisterType) throws -> UInt16 {
        switch register {
        case .BC: return BC
        case .DE: return DE
        case .HL: return HL
        case .SP: return SP
            
        case .i16: return read16(at: PC)

        default: throw CPUError.UnknownRegister
        }
    }
    
    func set(val: UInt16, for register: RegisterType) throws {
        switch register {
        case .BC: BC = val
        case .DE: DE = val
        case .HL: HL = val
        case .SP: SP = val

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
        
        subOpCycles = cycles
        do {
            switch op {
            case .nop:
                subOpCycles = 4
            case .ld8_8:
                try ld8_8(argTypes: args)
            case .ld16_16:
                try ld16_16(argTypes: args)
            case .ld16_8:
                try ld16_8(argTypes: args)
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
            print("Error executing opcodes \(error) \(op)")
        }
    }
}

// Extension defining instructions
// Terms:
// n an 8 bit value, nn a 16 bit value
extension CPU {
    func incPc(_ bytes: UInt16=1) {
        PC = (PC &+ bytes)
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
    
    // LD
    func ld8_16(argTypes: (RegisterType, RegisterType)) throws {
        let source = argTypes.1
        let target = argTypes.0
        
        let srcVal = try getVal8(for: source)
        try set(val: srcVal, for: target)
    }
    
    // LD 16 bit target with 8 bit value
    func ld16_8(argTypes: (RegisterType, RegisterType)) throws {
        
        let source = argTypes.1
        let target = argTypes.0

        let srcVal = try getVal8(for: source)
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
}

class RAM : MEMORY {

    let size: UInt16// in bytes
    var ram: [UInt8]
    
    enum RamError : Error {
        case Overflow
    }

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
    func replace(data: [UInt8], from address: UInt16) throws {
        //ram.insert(contentsOf: data, at: Int(address))
        let start = Int(address)
        let end = start+data.count
        guard end < ram.count else { throw RamError.Overflow }
        ram.replaceSubrange(start..<end, with: data)
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
        
//        ram.insert(data: bootBinary, at: 0x0000)
        try? ram.replace(data: bootBinary, from: 0x0000)
    }
}
