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
    var mmu: MMU
    var lcd: LCD
    var timer: Timer
    
    var systemClock: Double
    var clockRate: Double
    
    init(clock: Double) throws {
        clockRate = 0
        systemClock = clock
        cpu = CPU(sysClock: systemClock)
        
        mmu = try DmgMmu(size: 0x10000)
        lcd = LCD(sysClock: systemClock)
        
        // Connect lcd and mmu
        lcd.delegate = mmu
        mmu.delegateLcd = lcd
        // Connect the cpu with the memory
        cpu.mmu = mmu
        
        // Make a timer
        timer = Timer(sysClock: systemClock)
        timer.delegateMmu = mmu
        cpu.timer = timer
        cpu.reset()
    }
    
    func start() {
        
        clockRate = TimeInterval( 1 / systemClock )
        
        // Set the timer clock
        timer.selectClock(rate: 0x00)
//        print("Interval is \(interval)")
//        let clockTimer = Timer(timeInterval: interval, repeats: true, block: runCycle)
        
        // Load the rom first because the the boot rom will overwrite the first part
        bodgeRomLoader()
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
        
        // Tick the timer
        timer.tick()
        lcd.refresh()
        
        let endTime = DispatchTime.now()

        let elapsed = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        
        
        let clockInNs = clockRate * 1_000_000_000
    
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
        
        try? mmu.replace(data: bootBinary, from: 0x0000)
    }
    
    func bodgeRomLoader() {
        let binaryName = "bgbtest.gb"
        guard let path = Bundle.main.path(forResource: binaryName, ofType: nil),
            let romBinary = try? loadBinary(from: URL(fileURLWithPath: path))
            else {
                print("Failed to load rom binary.")
                return
        }
        
        try? mmu.replace(data: romBinary, from: 0x0000)
    }
}
