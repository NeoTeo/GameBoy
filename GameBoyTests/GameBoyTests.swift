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
