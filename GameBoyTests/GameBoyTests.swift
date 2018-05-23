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

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
