//
//  gameboy.swift
//  GameBoy
//
//  Created by Teo Sartori on 31/05/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

class Gameboy : SYSTEM {
    
    var cpu: CPU
    var ram: MEMORY
    var clockRate: Double
    
    init() {
        clockRate = 0
        cpu = CPU()
        ram = RAM(size: 0xFFFF)
        // Connect the cpu with the memory
        cpu.ram = ram
        cpu.reset()
    }
    
    func start(clock: Double) {
        
        clockRate = TimeInterval( 1 / clock )
//        print("Interval is \(interval)")
//        let clockTimer = Timer(timeInterval: interval, repeats: true, block: runCycle)
        
        // bodge some code into ram
        bodgeBootLoader()
        
        //runCycle(timer: Timer.init())
        runCycle()
//        RunLoop.current.add(clockTimer, forMode: .defaultRunLoopMode)
    }
    
    var totElaps: UInt64 = 0
    var count: UInt64 = 1
    

    func runCycle() {

        let startTime = DispatchTime.now()
        cpu.clockTick()
        let endTime = DispatchTime.now()

        let elapsed = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        
//        totElaps = (totElaps + elapsed)
//        let avg = totElaps / count
//        count += 1
        
        let clockInNs = clockRate * 1_000_000_000
//        if count % 100000 == 0 { print("avg elapsed \(avg). elapsed \(Double(elapsed)), ClockRate: \(clockInNs), diff: \(clockInNs - Double(elapsed))") }
        
    
        // Set a timer to fire in (clockRate - elapsed) seconds
        let interval = Int(max(clockInNs - Double(elapsed), 0))
        
        let teo = DispatchTime.now() + .nanoseconds(interval)
        
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: teo, execute: runCycle)
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
