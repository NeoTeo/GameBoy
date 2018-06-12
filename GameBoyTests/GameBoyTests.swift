//
//  GameBoyTests.swift
//  GameBoyTests
//
//  Created by Teo Sartori on 17/01/2017.
//  Copyright © 2017 Matteo Sartori. All rights reserved.
//

import XCTest
@testable import GameBoy

class GameBoyTests: XCTestCase {
    
    var gb: SYSTEM!
    
    let r16Ids: [CPU.ArgType] = [ .BC, .DE, .HL, .SP ]
    let r8Ids: [CPU.ArgType] = [.B, .D, .H, .C, .E, .L, .A, .HLptr]
    enum FlagTest {
        case Z(Bool)
        case N(Bool)
        case H(Bool)
        case C(Bool)
        
        func isSame(in val: UInt8) -> Bool {
            switch self {
            case .C(let state): return (((val >> 4) & 1) == 1) == state
            case .H(let state): return (((val >> 5) & 1) == 1) == state
            case .N(let state): return (((val >> 6) & 1) == 1) == state
            case .Z(let state): return (((val >> 7) & 1) == 1) == state
            }
        }
        
        func setSame(in val: UInt8) -> UInt8 {
            switch self {
            case .C(let s): return (val & ~(1 << 4)) | (s == true ? 1 : 0) << 4
            case .H(let s): return (val & ~(1 << 5)) | (s == true ? 1 : 0) << 5
            case .N(let s): return (val & ~(1 << 6)) | (s == true ? 1 : 0) << 6
            case .Z(let s): return (val & ~(1 << 7)) | (s == true ? 1 : 0) << 7
            }
        }
    }
    
    typealias TestState = (UInt8, UInt8,[FlagTest])
    
    // TestStartState consists of a tuple with:
    // * a tuple of the two register arguments,
    // * an array with initial flags and their state
    typealias TestStartState = ((UInt8, UInt8), [FlagTest])

    // TestEndState consists of a tuple with:
    // * an expected end value,
    // * an array of flags and their expected state
    typealias TestEndState =  (UInt8, [FlagTest])

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        gb = Gameboy()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
//        var gb = S
//        start(system: &gb)
    }
    
    func testSystem() {
        // Check initial state of flag register
        XCTAssert(gb.cpu.F.rawValue == 0xB0)
        print("Gameboy F register: \(String(gb.cpu.F.rawValue, radix: 2))")
    }
    
    func testCPUFRegister() {
        let cpu = gb.cpu
        cpu.F.Z = true
        cpu.F.N = true
        cpu.F.H = true
        cpu.F.C = true

        let rawVal = cpu.F.rawValue
        
        XCTAssert(((rawVal >> 7) & 0x1) == 0x1)
        XCTAssert(cpu.F.Z)
        
        XCTAssert(((rawVal >> 6) & 0x1) == 0x1)
        XCTAssert(cpu.F.N)

        XCTAssert(((rawVal >> 5) & 0x1) == 0x1)
        XCTAssert(cpu.F.H)

        XCTAssert(((rawVal >> 4) & 0x1) == 0x1)
        XCTAssert(cpu.F.C)

    }
    
    func testMiscellanous() {
    
        // Test SCF – simply sets the Carry flag
        var testVals: [(TestStartState, TestEndState)] = [(((0x00, 0x00), [.C(false)]), (0x00, [.C(true)]))]
        // Set up a list of the opcodes we want to test
        var opsToTest: [UInt8] = [0x37]
        
        test(ops: opsToTest, and: testVals)

        // Test CPL – sets the accumulator to its own complement.
        testVals = [(((0xFF, 0x00), [.H(false), .N(false)]), (0x00, [.H(true), .N(true)])),
                    (((0xAA, 0x00), [.H(false), .N(false)]), (0x55, [.H(true), .N(true)])),
        ]
        // Set up a list of the opcodes we want to test
        opsToTest = [0x2F]
        
        test(ops: opsToTest, and: testVals)
        
        // Test CCF – sets the C flag to its own complement.
        testVals = [(((0x00, 0x00), [.C(false), .N(true), .H(true)]), (0x00, [.C(true), .H(false), .N(false)])),
                    (((0x00, 0x00), [.C(true), .N(true), .H(true)]), (0x00, [.C(false), .H(false), .N(false)])),
        ]
        // Set up a list of the opcodes we want to test
        opsToTest = [0x3F]
        
        test(ops: opsToTest, and: testVals)

    }
    
    func testCp() {
        let testVals: [(TestStartState, TestEndState)] = [
        (((0x00, 0x01), [.C(false), .H(false)]), (0x00, [.C(true), .H(true), .N(true), .Z(false)])),
        (((0x01, 0x01), [.C(false), .H(false)]), (0x01, [.C(false), .H(false), .N(true), .Z(true)])),
        (((0x10, 0x01), [.C(false), .H(false)]), (0x10, [.C(false), .H(true), .N(true), .Z(false)])),
        ]
        // Set up a list of the opcodes we want to test
        let opsToTest: [UInt8] = [0xB8, 0xB9, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE]//, 0xBF]
    
        test(ops: opsToTest, and: testVals)
    }
    
    func testInc8HalfCarry() {
        
        gb.cpu.AF = 0x0f00
        gb.cpu.ram.write(at: 0x0000, with: 0x3C) // Add instruction INC A
        
        // Run four ticks that the INC A takes
        for _ in 0 ..< 4 { gb.cpu.clockTick() }
        
        let f = gb.cpu.F
        XCTAssert(f.H)
        XCTAssertFalse(f.Z || f.N || f.C)
        print("AF is " + String(format: "%2X", gb.cpu.AF))
    }

    func testDec8HalfCarry() {
        
        gb.cpu.AF = 0x01020
        gb.cpu.ram.write(at: 0x0000, with: 0x3D) // Add instruction INC A
        
        // Run four ticks that the INC A takes
        for _ in 0 ..< 4 { gb.cpu.clockTick() }
        
        let f = gb.cpu.F
        XCTAssert( f.H && f.N )
        XCTAssertFalse( f.Z || f.C )
        print("AF is " + String(format: "%2X", gb.cpu.AF))
    }

    func testInc8() {
        let testVals: [(TestStartState, TestEndState)] = [
            (((0x42, 0x00), []), (0x43, [.Z(false), .N(false)])),
            (((0xFF, 0x00), []), (0x00, [.Z(true), .N(false)])),
            (((0x0F, 0x00), []), (0x10, [.Z(false), .H(true), .N(false)])),
            ]
        // Set up a list of the opcodes we want to test
        let opsToTest: [UInt8] = [0x04, 0x14, 0x24, 0x0C, 0x1C, 0x2C, 0x3C]
        
        test(ops: opsToTest, and: testVals)
    }

    func testInc16() {
        
        // Make sure we stop if any of the tests fail
        continueAfterFailure = false

        let opCodes: [UInt8] = [0x03, 0x13, 0x23, 0x33]
        var opIdx = 0
        
        for reg in r16Ids {
            let startValue: UInt16 = 0x00FF
            // Set the register to a value
            try? gb.cpu.set(val: startValue, for: reg)
            // Set the memory location 0xC000 to the instruction opcode
            gb.cpu.ram.write(at: 0xC000, with: opCodes[opIdx])
            opIdx += 1
            // Set the PC to the instruction location
            gb.cpu.PC = 0xC000
            // Run the 8 ticks that the instruction takes
            for _ in 0 ..< 8 { gb.cpu.clockTick() }
            
            // Get the value for the register
            let endValue = try? gb.cpu.getVal16(for: reg)
            // Check that the value of the BC register is one larger
            XCTAssert(endValue == startValue+1)
        }
    }

    func testDec16() {
        
        // Make sure we stop if any of the tests fail
        continueAfterFailure = false

        let opCodes: [UInt8] = [0x0B, 0x1B, 0x2B, 0x3B]
        var opIdx = 0

        for reg in r16Ids {
            let startValue: UInt16 = 0x0100
            // Set the register to a value
            try? gb.cpu.set(val: startValue, for: reg)
            // Set the memory location 0xC000 to the instruction opcode
            gb.cpu.ram.write(at: 0xC000, with: opCodes[opIdx])
            opIdx += 1
            // Set the PC to the instruction location
            gb.cpu.PC = 0xC000
            // Run the 8 ticks that the instruction takes
            for _ in 0 ..< 8 { gb.cpu.clockTick() }
            
            // Get the value for the register
            let endValue = try? gb.cpu.getVal16(for: reg)
            // Check that the value of the BC register is one larger
            XCTAssert(endValue == startValue-1)
        }
    }

    func testIncDecHLptr() {
        
        // Set the memory location 0xC000 to the instruction INC (HL)
        gb.cpu.ram.write(at: 0xC000, with: 0x34)
        
        // Set the memory location at 0xC001 to the value 0x42
        gb.cpu.ram.write(at: 0xC001, with: 0x42)
        
        // Set the HL register to the address 1 byte below the instruction
        gb.cpu.HL = 0xC001
        
        // Set the PC to the memory location 0xC000
        gb.cpu.PC = 0xC000
        
        // Run 12 ticks that the INC (HL) takes
        for _ in 0 ..< 12 { gb.cpu.clockTick() }

        // Check that the value in memory location 0xC001 is now 0x43
        var incVal = gb.cpu.ram.read8(at: 0xC001)
        
        XCTAssert(incVal == 0x43)
        
        // Now decrement it again.
        // Set the memory location 0xC002 to the instruction DEC (HL)
        gb.cpu.ram.write(at: 0xC002, with: 0x35)

        // Run 12 ticks that the DEC (HL) takes
        for _ in 0 ..< 12 { gb.cpu.clockTick() }
        
        // Check that the value in memory location 0xC001 is now 0x42
        incVal = gb.cpu.ram.read8(at: 0xC001)
        
        XCTAssert(incVal == 0x42)

    }
    
    func testLd0x01() {
        // test  LD BC, i16
        // Clear the BC register
        gb.cpu.BC = 0x0000
        // Place the LD BC, i16 instruction in the top of RAM
        gb.cpu.ram.write(at: 0xC000, with: 0x01)
        // Place the 16 bit value to copy into the BC register in the next two bytes
        try? gb.cpu.ram.replace(data: [0x42, 0x69], from: 0xC001)
        // Set the PC to the top of RAM
        gb.cpu.PC = 0xC000
        // Run 12 ticks that the instruction takes
        for _ in 0 ..< 12 { gb.cpu.clockTick() }
        // Check that the BC register now contains 0x4269
        XCTAssert( gb.cpu.BC == 0x4269)
    }
    
    func testLd0x02() {
        // test LD (BC), A
        // Set the BC register to the address of the top of the RAM + 1 byte
        gb.cpu.BC = 0xC001
        // Set the A register to the value 0x42
        gb.cpu.A = 0x42
        // Set the byte at the top of RAM to be be the LD (BC), A instruction
        gb.cpu.ram.write(at: 0xC000, with: 0x02)
        // Set the PC to the top of the RAM
        gb.cpu.PC = 0xC000
        // Run 8 ticks that the instruction takes
        for _ in 0 ..< 8 { gb.cpu.clockTick() }
        // Read the RAM at the location BC is pointing to
        let resVal = gb.cpu.read8(at: gb.cpu.BC)
        // Check that the value matches the value in register A
        XCTAssert( resVal == gb.cpu.A )
    }
    
    // test LD (i16), SP
    // The instruction uses 3 bytes
    func testLd0x08() {
        let testVal: UInt16 = 0x4269
        // Clear the SP register
        gb.cpu.SP = testVal
        // Place the LD BC, i16 instruction in the top of RAM.
        gb.cpu.ram.write(at: 0xC000, with: 0x08)
        // Write the destination location as a 16 bit value in RAM just after the opcode.
        try? gb.cpu.ram.replace(data: [0xC0, 0x03], from: 0xC001)
        // Set the PC to the top of RAM
        gb.cpu.PC = 0xC000
        // Run the ticks that the instruction takes
        for _ in 0 ..< 20 { gb.cpu.clockTick() }
        
        let resVal = gb.cpu.read16(at: 0xC003)
        // Check that the result matches the testVal
        XCTAssert( resVal == testVal)
    }
    
    func testAdc() {

        // Tests consist of a tuple with:
        // a tuple of the two register arguments,
        // an array with initial flags and their state
        // an expected end value,
        // an array of flags and their expected state
        let tests: [(TestStartState, TestEndState)] = [
            (((0xFE, 0x01), [.C(true), .H(false)]), (0x00, [.C(true), .H(true), .Z(true)])),
            (((0xFE, 0x01), [.C(false), .H(false)]), (0xFF, [.C(false), .Z(false)])),
            (((0xFE, 0x02), [.C(false), .H(false)]), (0x00, [.C(true), .H(true)])),
            (((0xFD, 0x01), [.C(false), .H(false)]), (0xFE, [.C(false), .H(false)])),
            (((0xFD, 0x01), [.C(true), .H(false)]), (0xFF, [.C(false), .H(false)])),
            (((0x00, 0x00), [.C(true), .H(false)]), (0x01, [.C(false), .H(false)])),
        ]

        continueAfterFailure = false
        // Set up a list of the opcodes we want to test; all the LD 8bit, 8bit
        var opsToTest = [UInt8]()
        for i in 0x88..<0x8F { opsToTest.append(UInt8(i)) }
        opsToTest.append(0xCE)
        
        test(ops: opsToTest, and: tests)
    }
    
    func testAdd8_8() {
        
        continueAfterFailure = false
        // Set up a list of the opcodes we want to test; all the LD 8bit, 8bit
        var opsToTest = [UInt8]()
        for i in 0x80..<0x87 { opsToTest.append(UInt8(i)) }

        
        for op in opsToTest {

            // Write the opcode to RAM
            gb.cpu.write(at: 0xC000, with: op)
            gb.cpu.PC = 0xC001
            
            // Get the registers involved in the operation
            guard let (_,regs,ticks) = gb.cpu.ops[op] else {
                XCTFail("No entry for given opcode \(String(format: "%2X", op))")
                return
            }
            
            // Generate two random numbers and set the resulting addition as the test value
            let v1: UInt8 = UInt8.random(in: 0x00 ..< 0xFF)
            let v2: UInt8 = (regs.0 == regs.1) ? v1 : UInt8.random(in: 0x00 ..< 0xFF)
    
            let (testVal, overflow) = v1.addingReportingOverflow(v2)
            let halfCarry = gb.cpu.halfCarryOverflow(term1: v1, term2: v2)

            // Set the two registers to our values
            try? gb.cpu.set(val: v1, for: regs.0)
            try? gb.cpu.set(val: v2, for: regs.1)

            // Run the ticks that the instruction takes
            gb.cpu.PC = 0xC000
            for _ in 0 ..< ticks { gb.cpu.clockTick() }

            let resVal = try? gb.cpu.getVal8(for: regs.0)
        
            XCTAssert(resVal == testVal)
            let flags = gb.cpu.F
            print("resval \(resVal!) vs \(testVal) and flags: \(flags)")
            XCTAssert((flags.C == overflow)
                && (flags.H == halfCarry)
                && (flags.N == false)
                && (flags.Z == (testVal == 0))
            )
        }
    }

    func testAdd16_16() {
        continueAfterFailure = false
        // Set up a list of the opcodes we want to test; all the LD 8bit, 8bit
        let opsToTest: [UInt8] = [0x09, 0x19, 0x29, 0x39]
        
        for op in opsToTest {
            
            // Write the opcode to RAM
            gb.cpu.write(at: 0xC000, with: op)
            
            // Get the registers involved in the operation
            guard let (_,regs,ticks) = gb.cpu.ops[op] else {
                XCTFail("No entry for given opcode \(String(format: "%2X", op))")
                return
            }
            
            let v1: UInt16 = UInt16.random(in: 0x0000 ..< 0xFFFF)
            let v2: UInt16 = (regs.0 == regs.1) ? v1 : UInt16.random(in: 0x0000 ..< 0xFFFF)
            let (testVal, overflow) = v1.addingReportingOverflow(v2)
            let halfCarry = gb.cpu.halfCarryOverflow(term1: v1, term2: v2)

            // Set the two registers to our values
            try? gb.cpu.set(val: v1, for: regs.0)
            try? gb.cpu.set(val: v2, for: regs.1)
            
            // Run the ticks that the instruction takes
            gb.cpu.PC = 0xC000
            for _ in 0 ..< ticks { gb.cpu.clockTick() }
            
            let resVal = try? gb.cpu.getVal16(for: regs.0)
            
            XCTAssert(resVal == testVal)
            let flags = gb.cpu.F
            print("resval \(resVal!) vs \(testVal) and flags: \(flags)")
            XCTAssert((flags.C == overflow)
                && (flags.H == halfCarry)
                && (flags.N == false)
            )
        }

    }
    
    func testAnd() {
        // Flag register is always reset to 0x00 before starting the tests
        
        let testVals: [(TestStartState, TestEndState)] = [
            (((0x00, 0x01), []), (0x00, [.C(false), .H(true), .N(false), .Z(true)])),
            (((0x01, 0x01), []), (0x01, [.C(false), .H(true), .N(false), .Z(false)])),
            (((0xFF, 0xFE), []), (0xFE, [.C(false), .H(true), .N(false), .Z(false)])),
            ]
        // Set up a list of the opcodes we want to test
        // (exclude 0x97 as it subtracts itself and won't return the same result as the testval expects)
        let opsToTest: [UInt8] = [0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6]//, 0xA7]
        
        test(ops: opsToTest, and: testVals)
    }
    
    func testCall() {
        
        gb.cpu.SP = 0xC010

        // Set Z flag to false so the operation succeeds
        gb.cpu.F.Z = false
        
        // Write the instruction in the top of RAM.
        gb.cpu.ram.write(at: 0xC000, with: 0xC4)
        
        // Write the destination location as a 16 bit value in RAM just after the opcode.
        try? gb.cpu.ram.replace(data: [0xC0, 0x0A], from: 0xC001)
        
        // Set the PC to the top of RAM
        gb.cpu.PC = 0xC000
        // Run the ticks that the instruction takes
        for _ in 0 ..< 24 { gb.cpu.clockTick() }
        
        // Check that the PC is now 0xC00A
        XCTAssert( gb.cpu.PC == 0xC00A )
        
        // Assert that the stack pointer has moved back (stacks grow upward) by two bytes
        XCTAssert( gb.cpu.SP == 0xC00E )

        // Assert that the value pointed to by the stack pointer is the address we called from: 0xC004
        // First move the SP back to where it was
        gb.cpu.SP = 0xC010
        
        let startAddress = try! gb.cpu.getVal16(for: .SPptr)
        XCTAssert( startAddress == 0xC004 )
    }
    
    /* DAA truth table
     -----------------------------------------------------------------------------
     | N flag | C Flag  | H Flag | HEX value in | HEX value in | Number  | C flag|
     | Before | Before  | Before | upper digit  | lower digit  | added   | After |
     | DAA    | DAA     | DAA    | (bit 7-4)    | (bit 3-0)    | to byte | DAA   |
     |---------------------------------------------------------------------------|
     |   0    |    0    |   0    |     0-9      |     0-9      |   00    |   0   |
     |   0    |    0    |   0    |     0-8      |     A-F      |   06    |   0   |
     |   0    |    0    |   1    |     0-9      |     0-3      |   06    |   0   |
     |   0    |    0    |   0    |     A-F      |     0-9      |   60    |   1   |
     |   0    |    0    |   0    |     9-F      |     A-F      |   66    |   1   |
     |   0    |    0    |   1    |     A-F      |     0-3      |   66    |   1   |
     |   0    |    1    |   0    |     0-2      |     0-9      |   60    |   1   |
     |   0    |    1    |   0    |     0-2      |     A-F      |   66    |   1   |
     |   0    |    1    |   1    |     0-3      |     0-3      |   66    |   1   |
     |---------------------------------------------------------------------------|
     |   1    |    0    |   0    |     0-9      |     0-9      |   00    |   0   |
     |   1    |    0    |   1    |     0-8      |     6-F      |   FA    |   0   |
     |   1    |    1    |   0    |     7-F      |     0-9      |   A0    |   1   |
     |   1    |    1    |   1    |     6-F      |     6-F      |   9A    |   1   |
     |---------------------------------------------------------------------------|
     */
    func testDaa() {
        let testVals: [(TestStartState, TestEndState)] = [
            (((0x11, 0x00), [.C(false), .H(false), .N(false)]), (0x11, [.C(false), .H(false), .N(false), .Z(false)])),
            (((0x1A, 0x00), [.C(false), .H(false), .N(false)]), (0x20, [.C(false), .H(false), .N(false), .Z(false)])),
            (((0x93, 0x00), [.C(false), .H(true), .N(false)]), (0x99, [.C(false), .H(false), .N(false), .Z(false)])),
            (((0x29, 0x00), [.C(true), .H(false), .N(false)]), (0x89, [.C(true), .H(false), .N(false), .Z(false)])),
            (((0x33, 0x00), [.C(true), .H(true), .N(false)]), (0x99, [.C(true), .H(false), .N(false), .Z(false)])),
            (((0x9A, 0x00), [.C(false), .H(false), .N(false)]), (0x00, [.C(true), .H(false), .N(false), .Z(true)])),
            // negative
            (((0x99, 0x00), [.C(false), .H(false), .N(true)]), (0x99, [.C(false), .H(false), .N(true), .Z(false)])),
            (((0x86, 0x00), [.C(false), .H(true), .N(true)]), (0x80, [.C(false), .H(false), .N(true), .Z(false)])),
            (((0x79, 0x00), [.C(true), .H(false), .N(true)]), (0x19, [.C(true), .H(false), .N(true), .Z(false)])),
            (((0xFF, 0x00), [.C(true), .H(true), .N(true)]), (0x99, [.C(true), .H(false), .N(true), .Z(false)])),
            ]
        
        test(ops: [0x27], and: testVals, customRegs: (.A, .noReg))
    }
    
    func testJrNz() {
        
        // Clear the F register
        gb.cpu.F.rawValue = 0x00
        let zFlag: [Bool] = [false, false, false, true]
        let offs: [UInt8] = [0x02, 0x00, 0x86, 0x42]
        let pcLoc: [UInt16] = [0xC004, 0xC002, 0xBF88, 0xC001]
        
        for i in 0 ..< offs.count {
            gb.cpu.F.Z = zFlag[i]
            // Place the JR NZ, i8 instruction in the top of RAM.
            gb.cpu.ram.write(at: 0xC000, with: 0x20)
            
            // Write the jump offset in RAM in the byte after the opcode.
            gb.cpu.ram.write(at: 0xC001, with: offs[i])
            
            // Set the PC to the top of RAM
            gb.cpu.PC = 0xC000
            // Run the ticks that the instruction takes
            for _ in 0 ..< 12 { gb.cpu.clockTick() }
            
            // Check that the PC matches the expected location            
            XCTAssert( gb.cpu.PC == pcLoc[i])
        }
    }
    
    func testLd16_16() {
        
    }
    
    func testLd8_8() {
    
        continueAfterFailure = false
        
        func checkForHLptrIncDec(regs: (CPU.ArgType, CPU.ArgType)) -> (CPU.ArgType, CPU.ArgType) {
            var retRegs = regs
            if (regs.0 == .HLptrDec) || (regs.0 == .HLptrInc) {
                retRegs.0 = .HLptr
                gb.cpu.HL = 0xC003
            }
            if (regs.1 == .HLptrDec) || (regs.1 == .HLptrInc) {
                retRegs.1 = .HLptr
                gb.cpu.HL = 0xC003
            }

            return retRegs
        }

        // Set up a list of the opcodes we want to test; all the LD 8bit, 8bit
        var opsToTest = [UInt8]()
        var i: UInt8 = 2
        while i < 0x3F { opsToTest.append(i) ; i += 4 }
        for i in 0x40 ..< 0x80 {
            if i != 0x76 { opsToTest.append(UInt8(i)) }
        }
        opsToTest += [0xE0, 0xF0, 0xE2, 0xF2, 0xEA, 0xFA]
        

        // FIXME: move testval inside the ops loop
        // Set a random number as the test value
        let testVal: UInt8 = UInt8.random(in: 0x00 ..< 0xFF)
        for op in opsToTest {
            
            // Write the opcode to RAM
            gb.cpu.write(at: 0xC000, with: op)
            // Clear High Ram and the i8 following the opcode.
            gb.cpu.write(at: 0xFF00, with: UInt16(0x0000))
            gb.cpu.write(at: 0xC001, with: UInt8(0x00))
            // Get the registers involved in the operation
            guard let (_,regs,ticks) = gb.cpu.ops[op] else {
                XCTFail("No entry for given opcode \(String(format: "%2X", op))")
                return
            }
            
            // Set the PC to the address immediately after the opcode in case our
            // source register is an immediate value which is expected to follow it
            gb.cpu.PC = 0xC001
            // We need to set the value that the source register/location will provide.
            // If the source is an HLptrInc or HLptrDec we need to set the HL to a
            // known address and to change the source register to an HLptr to avoid
            // the HL getting [inc|dec]remented; checkForHLptrIncDec handles this.
            let (destReg, sourceReg) = checkForHLptrIncDec(regs: regs)
            // Set the source register to our test value we can check against
            try? gb.cpu.set(val: testVal, for: sourceReg)
            
            // Set the PC to the top of the RAM
            gb.cpu.PC = 0xC000
            // Run the ticks that the instruction takes
            for _ in 0 ..< ticks { gb.cpu.clockTick() }
            
            // If the instruction we just executed contained an HLptrInc/HLptrDec source
            // or destination register then has [inc|dec]remented the HL by one
            // and we now need to reset it so we can read it.
            _ = checkForHLptrIncDec(regs: regs)

            // Set PC to just after opcode in case the getVal needs to read an immediate value.
            gb.cpu.PC = 0xC001
            // Read the value at the destination address
            let resVal = try! gb.cpu.getVal8(for: destReg)
            // Check that the value matches the value in register A
            XCTAssert(resVal == testVal, "Error for op \(op)")

        }
    }

    func testOr() {
        let testVals: [(TestStartState, TestEndState)] = [
            (((0x00, 0x01), []), (0x01, [.Z(false)])),
            (((0xAA, 0x55), []), (0xFF, [.Z(false)])),
            (((0xAA, 0xAA), []), (0xAA, [.Z(false)])),
            ]
        // Set up a list of the opcodes we want to test
        // (exclude 0xB7 as it subtracts itself and won't return the same result as the testval expects)
        let opsToTest: [UInt8] = [0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6]// , 0xB7]
        
        test(ops: opsToTest, and: testVals)
    }
    
    func testPopAF() {
        // Clear the F register
        gb.cpu.F.rawValue = 0x00
//        let zFlag: [Bool] = [false, false, false, true]
//        let offs: [UInt8] = [0x02, 0x00, 0x86, 0x42]
//        let pcLoc: [UInt16] = [0xC004, 0xC002, 0xBF88, 0xC001]
        
//        for i in 0 ..< offs.count {
//            gb.cpu.F.Z = zFlag[i]
            // Place the instruction in the top of RAM.
            gb.cpu.ram.write(at: 0xC000, with: 0xF1)
        
            // Set the stack pointer to point to a specific address
            gb.cpu.SP = 0xC005
        
            // Write two bytes of known values at the location pointed to by the SP
            gb.cpu.ram.write(at: 0xC005, with: 0x42)
            gb.cpu.ram.write(at: 0xC006, with: 0xA0)
            
            // Set the PC to the top of RAM
            gb.cpu.PC = 0xC000
        
            // Run the ticks that the instruction takes
            for _ in 0 ..< 12 { gb.cpu.clockTick() }
            
            // Check that the PC matches the expected data
            XCTAssert( gb.cpu.A == 0x42)
            XCTAssert( gb.cpu.F.rawValue == 0xA0)
//        }

    }

    func testPush() {
        
        gb.cpu.AF = 0x4260
        
        // Place the instruction in the top of RAM.
        gb.cpu.ram.write(at: 0xC000, with: 0xF5)
        
        // Set the stack pointer to point to a specific address
        gb.cpu.SP = 0xC005
        
        // Set the PC to the top of RAM
        gb.cpu.PC = 0xC000
        
        // Run the ticks that the instruction takes
        for _ in 0 ..< 16 { gb.cpu.clockTick() }
        
        // Read the value at the location (originally) pointed to by the SP
        let val1 = gb.cpu.ram.read8(at: 0xC005)
        let val2 = gb.cpu.ram.read8(at: 0xC006)
        
        // Check that the PC matches the expected data
        XCTAssert( val1 == 0x42)
        XCTAssert( val2 == 0x60)

    }
    
    // CB prefix instruction
    func testRlc() {
//        let testVals: [(TestStartState, TestEndState)] = [
//            (((0x00, 0x00), [.C(false), .H(false)]), (0x03, [.C(true), .H(false), .N(false), .Z(false)])),
//            ]
//        // Set up a list of the opcodes we want to test
//        // (exclude 0x9F as it subtracts itself and won't return the same result as the testval expects)
//        let opsToTest: [UInt8] = [0x07]
//
//        test(ops: opsToTest, and: testVals)
    }


    func testRla() {
        
        let testVals: [(TestStartState, TestEndState)] = [
            (((0x81, 0x00), [.C(false), .H(false)]), (0x02, [.C(true), .H(false), .N(false), .Z(false)])),
            (((0x81, 0x00), [.C(true), .H(false)]), (0x03, [.C(true), .H(false), .N(false), .Z(false)])),
            (((0x41, 0x00), [.C(true), .H(false)]), (0x83, [.C(false), .H(false), .N(false), .Z(false)])),
            (((0x41, 0x00), [.C(false), .H(false)]), (0x82, [.C(false), .H(false), .N(false), .Z(false)])),
            ]
        
            test(ops: [0x17], and: testVals, customRegs: (.A, .noReg))
    }

    func testRlca() {
        
        let testVals: [(TestStartState, TestEndState)] = [
            (((0x81, 0x00), [.C(false), .H(false)]), (0x03, [.C(true), .H(false), .N(false), .Z(false)])),
            (((0x81, 0x00), [.C(true), .H(false)]), (0x03, [.C(true), .H(false), .N(false), .Z(false)])),
            (((0x80, 0x00), [.C(false), .H(false)]), (0x01, [.C(true), .H(false), .N(false), .Z(false)])),
            (((0x41, 0x00), [.C(false), .H(false)]), (0x82, [.C(false), .H(false), .N(false), .Z(false)])),
            ]
        
        test(ops: [0x07], and: testVals, customRegs: (.A, .noReg))
    }

    func testRra() {
        let testVals: [(TestStartState, TestEndState)] = [
            (((0x01, 0x00), [.C(false), .H(false)]), (0x00, [.C(true), .H(false), .N(false), .Z(false)])),
            (((0x01, 0x00), [.C(true), .H(false)]), (0x80, [.C(true), .H(false), .N(false), .Z(false)])),
            (((0x00, 0x00), [.C(true), .H(false)]), (0x80, [.C(false), .H(false), .N(false), .Z(false)])),
            ]
        
        test(ops: [0x1F], and: testVals, customRegs: (.A, .noReg))
    }

    func testRrca() {
        let testVals: [(TestStartState, TestEndState)] = [
            (((0x01, 0x00), [.C(false), .H(false)]), (0x80, [.C(true), .H(false), .N(false), .Z(false)])),
            (((0x01, 0x00), [.C(true), .H(false)]), (0x80, [.C(true), .H(false), .N(false), .Z(false)])),
            (((0x00, 0x00), [.C(true), .H(false)]), (0x00, [.C(false), .H(false), .N(false), .Z(false)])),
            ]
        
        test(ops: [0x0F], and: testVals, customRegs: (.A, .noReg))
    }
    
    func testSbc() {
        let testVals: [(TestStartState, TestEndState)] = [
            (((0x00, 0x01), [.C(false), .H(false)]), (0xFF, [.C(true), .H(true), .N(true), .Z(false)])),
            (((0x00, 0x01), [.C(true), .H(false)]), (0xFE, [.C(true), .H(true), .N(true), .Z(false)])),
            (((0x01, 0x01), [.C(false), .H(false)]), (0x00, [.C(false), .H(false), .N(true), .Z(true)])),
            (((0x01, 0x01), [.C(true), .H(false)]), (0xFF, [.C(true), .H(true), .N(true), .Z(false)])),
            (((0x10, 0x01), [.C(false), .H(false)]), (0x0F, [.C(false), .H(true), .N(true), .Z(false)])),
            ]
        // Set up a list of the opcodes we want to test
        // (exclude 0x9F as it subtracts itself and won't return the same result as the testval expects)
        let opsToTest: [UInt8] = [0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E]//, 0x9F]
        
        test(ops: opsToTest, and: testVals)
    }
    
    func testSub() {
        let testVals: [(TestStartState, TestEndState)] = [
            (((0x00, 0x01), [.C(false), .H(false)]), (0xFF, [.C(true), .H(true), .N(true), .Z(false)])),
            ]
        // Set up a list of the opcodes we want to test
        let opsToTest: [UInt8] = [0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0xD6]
        
        test(ops: opsToTest, and: testVals)
    }
    
    func testXor() {
        let testVals: [(TestStartState, TestEndState)] = [
            (((0x00, 0x01), []), (0x01, [.Z(false)])),
            (((0xAA, 0x55), []), (0xFF, [.Z(false)])),
            (((0xAA, 0xAA), []), (0x00, [.Z(true)])),
            ]
        // Set up a list of the opcodes we want to test
        // (exclude 0xAF as it subtracts itself and won't return the same result as the testval expects)
        let opsToTest: [UInt8] = [0xA8, 0xA9, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE]// , 0xAF]
        
        test(ops: opsToTest, and: testVals)
    }
    
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}

// Test CB prefix opcodes
extension GameBoyTests {
    
    func testBit() throws {
    
        let testVals: [UInt8 : [(TestStartState, TestEndState)]] = [
            0x40 : [(((0xFE, 0x00), []), (0x00, [.Z(true)])),
                    (((0x01, 0x00), []), (0x00, [.Z(false)]))],
            0x41 : [(((0xFE, 0x00), []), (0x00, [.Z(true)])),
                    (((0x01, 0x00), []), (0x00, [.Z(false)]))],
            0x48 : [(((0xFD, 0x00), []), (0x00, [.Z(true)])),
                    (((0x02, 0x00), []), (0x00, [.Z(false)]))],
            0x50 : [(((0xFB, 0x00), []), (0x00, [.Z(true)])),
                    (((0x04, 0x00), []), (0x00, [.Z(false)]))],
            0x58 : [(((0xF7, 0x00), []), (0x00, [.Z(true)])),
                    (((0x08, 0x00), []), (0x00, [.Z(false)]))],
            0x60 : [(((0xEF, 0x00), []), (0x00, [.Z(true)])),
                    (((0x10, 0x00), []), (0x00, [.Z(false)]))],
            0x68 : [(((0xDF, 0x00), []), (0x00, [.Z(true)])),
                    (((0x20, 0x00), []), (0x00, [.Z(false)]))],
            0x70 : [(((0xBF, 0x00), []), (0x00, [.Z(true)])),
                    (((0x40, 0x00), []), (0x00, [.Z(false)]))],
            0x78 : [(((0x7F, 0x00), []), (0x00, [.Z(true)])),
                    (((0x80, 0x00), []), (0x00, [.Z(false)]))],
            ]
        
        // Test all BIT operations
        for opcode in 0x40 ..< 0x80 {
            
            let op = UInt8(opcode)
            
            // Get the registers involved in the operation
            guard let (_,regs,_) = gb.cpu.cbOps[op] else {
                XCTFail("No entry for given opcode \(String(format: "%2X", op))")
                return
            }
            
            // Place the CB instruction in the top of RAM.
            gb.cpu.ram.write(at: 0xC000, with: 0xCB)
            gb.cpu.ram.write(at: 0xC001, with: op)

            guard let testStates = testVals[op] else { continue }
            
            for testState in testStates {
                
                let testStartState = testState.0
                let testEndState = testState.1
                let startVal = testStartState.0.0
                
                // Set affected register to a known value
                try gb.cpu.set(val: startVal, for: regs.1)
                
                // Set the PC to the top of RAM
                gb.cpu.PC = 0xC000

                // Run the ticks that the instruction takes
                for _ in 0 ..< 12 { gb.cpu.clockTick() }
        
                let endFlags = testEndState.1
                // Check the flags
                for flag in endFlags { XCTAssert(flag.isSame(in: gb.cpu.F.rawValue)) }
            }
        }
    }
}

// Helper functions that are not specific tests themselves.
extension GameBoyTests {
    
    typealias RegisterPair = (CPU.ArgType, CPU.ArgType)
    
    
    /// Test function.
    ///
    /// - Parameters:
    ///   - testOps: An array of opcodes to test
    ///   - testVals: an array of start states and ends states for each test.
    ///   - customRegs: an optional pair of registers to use for the test instead
    ///     of the ones associated with the instruction in the optable. If nil the
    ///     normal registers are used.
    func test(ops testOps: [UInt8], and testVals: [(TestStartState, TestEndState)], customRegs: RegisterPair? = nil) {
        
        continueAfterFailure = false
        
        gb.cpu.F.rawValue = 0x00 // reset flags
        for op in testOps {
            // Write the opcode to RAM
            gb.cpu.write(at: 0xC000, with: op)
            
            // Get the registers involved in the operation
            guard let (_,regs,ticks) = gb.cpu.ops[op] else {
                XCTFail("No entry for given opcode \(String(format: "%2X", op))")
                return
            }

            // custom registers override the ones fetched from the op table (for testing)
            let testRegs = customRegs ?? regs
            
            multiTest(op: op, regs: testRegs, ticks: ticks, testVals:  testVals)
        }
    }
    
    
    /// Do multiple tests of a given instruction.
    ///
    /// - Parameters:
    ///   - op: the opcode of the instruction to test
    ///   - regs: the source and destination registers the instruction uses.
    ///   - ticks: the number of ticks the instruction should take
    ///   - testVals: the initial settings and expected outcome for each test.
    func multiTest(op: UInt8, regs: (CPU.ArgType, CPU.ArgType), ticks: UInt8, testVals: [(TestStartState, TestEndState)]) {
        for t in testVals {
            // Extract the start states
            let startState = t.0
            
            let args = startState.0
            let flags = startState.1
            
            let v1: UInt8 = args.0
            let v2: UInt8 = (regs.1 == regs.0) ? v1 : args.1
            // Set up the flags we're interested in
            var newFlagRegister = gb.cpu.F.rawValue
            for flag in flags { newFlagRegister = flag.setSame(in: newFlagRegister) }
            gb.cpu.F.rawValue = newFlagRegister
            
            // Set PC just after opcode in case we're loading an immediate value from subsequent bytes
            gb.cpu.PC = 0xC001
            
            // Set the two registers to our values
            if regs.0 != .noReg { try? gb.cpu.set(val: v1, for: regs.0) }
            if regs.1 != .noReg { try? gb.cpu.set(val: v2, for: regs.1) }
            
            // Run the ticks that the instruction takes
            gb.cpu.PC = 0xC000
            for _ in 0 ..< ticks { gb.cpu.clockTick() }
            
            // Extract the end states
            let endState = t.1
            let testVal = endState.0
            let endFlags = endState.1
            
            // Read the destination register to confirm the result
            if regs.0 != .noReg {
                let resVal = try! gb.cpu.getVal8(for: regs.0)
                XCTAssert(resVal == testVal)
            }
            // Check the flags
            for flag in endFlags { XCTAssert(flag.isSame(in: gb.cpu.F.rawValue)) }
        }
    }
}
