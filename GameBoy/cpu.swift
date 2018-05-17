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
}

protocol SYSTEM {
    var cpu: CPU { get }
    var ram: MEMORY { get }
    
    func start(clockRate: Int)
}

/// LR35902 CPU
class CPU {
    var PC: UInt16 = 0      // Program Counter
    var SP: UInt16 = 0      // Stack Pointer
    
    /// registers
    var A: UInt8 = 0
    var B: UInt8 = 0
    var C: UInt8 = 0
    var D: UInt8 = 0
    var E: UInt8 = 0
    
    var H: UInt8 = 0
    var L: UInt8 = 0
    
    struct FlagRegister : OptionSet {
        let rawValue: UInt8
        
        static let Z = FlagRegister(rawValue: 1 << 7)     /// Zero
        static let N = FlagRegister(rawValue: 1 << 6)     /// Add/Sub (BCD)
        static let H = FlagRegister(rawValue: 1 << 5)     /// Half carry (BCD)
        static let C = FlagRegister(rawValue: 1 << 4)     /// carry
    }
    
    var F: FlagRegister = [] // init clear
    
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
        case BCloc
        case DE
        case HL
        case d8
        case d16
        case a8
        case a16
    }
    
    enum OpType {
        case NOP
        case LD
        case INC
        case DEC
        case RLCA
        case ADD
        case RRCA
        case STOP
        case RLA
    }
        
    enum Inst {
        case NOP(cycles: UInt8)
        case LD(target: ArgType, source: ArgType, cycles: UInt8)
    }

    let instructions: [Inst] = [
        Inst.NOP(cycles: 4),                                   // 0x00
        Inst.LD(target: .BC, source: .d16, cycles: 12),        // 0x01
        Inst.LD(target: .BCloc, source: .A, cycles: 8)         // 0x02
    ]
    
    var ram: MEMORY!
    var subOpCycles: UInt8 = 0
    
    func reset() {
        // Set initial register values as in DMG/GB
        AF = 0x01B0
        BC = 0x0013
        DE = 0x00D8
        HL = 0x014D
        SP = 0xFFFE
        PC = 0x0100
    }
    
    
    func incPc() {
        PC = (PC &+ 1)
    }
    
    func clockTick() {

        subOpCycles -= 1
        if subOpCycles > 0 {  return }

        /// Read from ram
        let opcode = ram.read8(at: PC)
        incPc()

        print("PC is \(PC)")
        print("opcode is \(opcode)")
        
//        let (opType, op, arg1, arg2, cycles) = instructions[Int(opcode)]
        let op = instructions[Int(opcode)]
        
        switch op {
        case .NOP(subOpCycles):
            print("NOP")
            
        case .LD(let target, let source, subOpCycles):
            
            switch (target, source) {
            case (.BC, .a16):
                BC = ram.read16(at: PC)
            case (.BCloc, .A):
                ram.write(at: BC, with: A)
                
            default:
                print("no happy")
            }
            
            print("LD")
        default:
            print("unsupported operation \(op)")
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
//        print("opcode is \(opcode)")
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
//            BC += 1
//            subOpCycles = 8
//
//        case 0x04:  /// INC B
//            B += 1
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
//        default:
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
        ram.write(at: 0x100, with: 0x01)
        RunLoop.current.add(clockTimer, forMode: .defaultRunLoopMode)
    }
    
    func runCycle(timer: Timer) {
        cpu.clockTick()
    }
}
