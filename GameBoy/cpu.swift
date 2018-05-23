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
    var subOpCycles: UInt8 = 4
    
    // FIXME: Turn this into an array.

    typealias OpHandler = Any // (inout UInt8)->Void
//    var ops: [UInt8 : (String, OpHandler, UInt8)] = [:]
    // An op consists of an instruction id, an arguments string and a cycle count.
    var ops =  [UInt8 : (Any, String?, UInt8)]()
    func reset() {
        // Set initial register values as in DMG/GB
        AF = 0x01B0
        BC = 0x0013
        DE = 0x00D8
        HL = 0x014D
        SP = 0xFFFE
        PC = 0x0000
        
        ops[0x3C] = (inc8, "A", 4)
        ops[0x04] = (inc8, "B", 4)
        ops[0x3D] = (dec8, "A", 4)
        //        ops[0x3C] = ("A", inc8, 4)
        //        ops[0x04] = ("B", inc8, 4)

    }
    
    
    func incPc() {
        PC = (PC &+ 1)
    }


    // INC A, B, C, D, E, H, L, (HL)
    // Flags affected:
    // Z - Set if result is zero.
    // N - Reset.
    // H - Set if carry from bit 3.
    // C - Not affected.
    func inc8(n: inout UInt8) {
    
        // increment n register and wrap to 0 if overflowed.
        n = n &+ 1
        
        // Set F register correctly
        F.Z = (n == 0)
        F.H = (n == 0x10) // If n was 0xf then we had carry from bit 3.
        F.N = false
    }
    
    // INC BC, DE, HL, SP
    // Flags unaffected
    func inc16(nn: inout UInt16) {
        nn = nn &+ 1
    }
    
    // DEC A, B, C, D, E, H, L, (HL)
    func dec8(n: inout UInt8) {
        n = n &- 1
   
        F.Z = (n == 0)
        F.H = (n == 0xf) // H set if no borrow from bit 4 ?
        F.N = true // N set to 1
    }
    
    // DEC BC, DE, HL, SP
    func dec16(nn: inout UInt16) {
        nn = nn &- 1
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
        switch op {
        case let (operation as (inout UInt8)->()):
            nArgCaller(handler: operation, n: args)
            
        case let (operation as (inout UInt8, inout UInt8)->()):
            print("two 8 bit args")
        
        case let (operation as (inout UInt16)->()):
            nArgCaller(handler: operation, n: args)
        
        case let (operation as (inout UInt16, inout UInt16)->()):
            print("two 16 bit args")
            
        default:
            print("shite")
        }
//        if let operation = op as? (inout UInt8)->() {
//            nArgCaller(handler: operation, n: nId1)
//        }
    }
    
    func nArgCaller(handler: (inout UInt8)->(), n: String?) {
        switch n {
        case "A": handler(&A)
        case "B": handler(&B)
        case "C": handler(&C)
        case "D": handler(&D)
        case "E": handler(&E)
        case "H": handler(&H)
        case "L": handler(&L)
        default:
            print("shit")
        }
    }
    
//    func nArgCaller(handler: (inout UInt8, inout UInt8)->(), n: String?) {
//
//        guard let n1 = arg8Ptr(from: n), let n2 = arg8Ptr(from: <#T##String#>)
//        switch n {
//        case "A_B": handler(&A, &B)
//        case "B": handler(&B)
//        case "C": handler(&C)
//        case "D": handler(&D)
//        case "E": handler(&E)
//        case "H": handler(&H)
//        case "L": handler(&L)
//        default:
//            print("shit")
//        }
//    }

    func nArgCaller(handler: (inout UInt16)->(), n: String?) {
        switch n {
        case "BC": handler(&BC)
        case "DE": handler(&DE)
        case "HL": handler(&HL)
        case "SP": handler(&SP)
        default:
            print("shit")
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
