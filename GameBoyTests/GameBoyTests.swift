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

    let r16Ids: [CPU.RegisterType] = [ .BC, .DE, .HL, .SP ]
    let r8Ids: [CPU.RegisterType] = [.B, .D, .H, .C, .E, .L, .A]
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
    }
    
    func testInc8() {
        
        // Make sure we stop if any of the tests fail
        continueAfterFailure = false
        
        // A test consists of a start value, an end value and an array of FlagTests
        // which declare the expected flag setting at the end of the test.
        // Perhaps I should use a unionset for the flag testing instead...
        let tests: [(UInt8, UInt8,[FlagTest])] = [(0x42, 0x43,[.Z(false), .N(false)]),
                                                  (0xFF, 0x00,[.Z(true), .N(false)]),
                                                  (0x0F, 0x10,[.Z(false), .H(true), .N(false)])]
        
        let opCodes: [UInt8] = [0x04, 0x14, 0x24, 0x0C, 0x1C, 0x2C, 0x3C]
        var opIdx = 0
        
        for reg in r8Ids {
            
            // We test each register multiple times for different flag states
            for (sv, ev, ft) in tests {
            
                // set start value such that the first inc will cause a half carry
                let startValue: UInt8 = sv
                // Set the register to a value
                try? gb.cpu.set(val: startValue, for: reg)
                // Set the memory location 0xC000 to the instruction opcode
                gb.cpu.ram.write(at: 0xC000, with: opCodes[opIdx])
                
                // Set the PC to the instruction location
                gb.cpu.PC = 0xC000
                // Run the number of ticks the instruction takes
                for _ in 0 ..< 4 { gb.cpu.clockTick() }
                
                // Get the value for the register
                guard let endValue = try? gb.cpu.getVal8(for: reg) else {
                    XCTFail("testInc8 could not get value for register \(reg)")
                    break
                }
                // Check that the value of the BC register is one larger
                XCTAssert(endValue == ev)
                
                // check flags
//                let flags = gb.cpu.F.rawValue
//                for t in ft {
//                    XCTAssert(t.isSet(in: flags))
//                }
            }
            opIdx += 1
        }
        // We should check the flags too.
        // Check Z 1 H
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
        gb.cpu.ram.insert(data: [0x42, 0x69], at: 0xC001)
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
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
