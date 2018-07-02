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
        lcd.delegateMmu = mmu
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
        
        clockRate = systemClock //TimeInterval( 1 / systemClock )
        
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
        
//        dbgPrintAvgs()
        //dbgPrintRegisters()
//        RunLoop.current.add(clockTimer, forMode: .defaultRunLoopMode)
    }
    
    var totElaps: UInt64 = 0
    var count: UInt64 = 1
    
    var cpuAvg: Double = 0
    var timerAvg: Double = 0
    var lcdAvg: Double = 0
    var cycleAvg: Double = 0
    var cycleLast: DispatchTime = DispatchTime(uptimeNanoseconds: 0)
    var testTimer: DispatchSourceTimer?
    
    var accu: UInt32 = 0
    var cnt: UInt32 = 0
    var gtot = [UInt32]()
    
    let cycleQ = DispatchQueue.global(qos: .userInitiated)
    
    func runCycle() {
        let startTime = DispatchTime.now()
//
//        cycleAvg = dbgCalcAvgTime(timeDiff: Double(startTime.uptimeNanoseconds - cycleLast.uptimeNanoseconds), for: cycleAvg)
////        print("delta: \(1_000_000_000 / Double(startTime.uptimeNanoseconds - cycleLast.uptimeNanoseconds))")
//        cycleLast = startTime
        
        cpu.clockTick()
//        let cpuTime = DispatchTime.now()
//        cpuAvg = dbgCalcAvgTime(timeDiff: Double(cpuTime.uptimeNanoseconds - startTime.uptimeNanoseconds), for: cpuAvg)
        // Tick the timer
        timer.tick()
//        let timerTime = DispatchTime.now()
//        timerAvg = dbgCalcAvgTime(timeDiff: Double(timerTime.uptimeNanoseconds - cpuTime.uptimeNanoseconds), for: timerAvg)
//
        lcd.refresh()
//        let lcdTime = DispatchTime.now()
//        lcdAvg = dbgCalcAvgTime(timeDiff: Double(lcdTime.uptimeNanoseconds - timerTime.uptimeNanoseconds), for: lcdAvg)
//
        let endTime = DispatchTime.now()

        let elapsed = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        accu = accu &+ UInt32(elapsed)
        cnt += 1
        if (accu & 0xFFFF) == 0 {
            
            gtot.append(accu/cnt)
            let avg = Int(gtot.reduce(0, +)) / gtot.count
            print("Avg: \(avg)")
            accu = 0
            cnt = 0
        }
//        let clockInNs = clockRate * 1_000_000_000
        let clockInNs = 1_000_000_000 / clockRate
 
        // Set a timer to fire in (clockRate - elapsed) seconds
        let interval = Int(max(clockInNs - Double(elapsed), 0))
        
        let teo = DispatchTime.now() + .nanoseconds(interval)
        
//        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: teo, execute: runCycle)
        cycleQ.asyncAfter(deadline: teo, execute: runCycle)
//        testTimer = DispatchSource.makeTimerSource()
//        testTimer?.setEventHandler(handler: runCycle)
//        testTimer?.schedule(deadline: teo)
//        testTimer?.activate()
    }
    
    
    func bodgeBootLoader() {
        let binaryName = "DMG_ROM.bin"
        guard let path = Bundle.main.path(forResource: binaryName, ofType: nil),
            let bootBinary = try? loadBinary(from: URL(fileURLWithPath: path))
            else {
                print("Failed to load boot binary.")
                return
        }
        
        //try? mmu.replace(data: bootBinary, from: 0x0000)
        mmu.bootRom = bootBinary
    }
    
    func bodgeRomLoader() {
//        let binaryName = "pkb.gb"
//        let binaryName = "cpu_instrs.gb"
        let binaryName = "02interrupts.gb"
//        let binaryName = "01special.gb" // passes
//        let binaryName = "bgbtest.gb"
        guard let path = Bundle.main.path(forResource: binaryName, ofType: nil),
            let romBinary = try? loadBinary(from: URL(fileURLWithPath: path))
            else {
                print("Failed to load rom binary.")
                return
        }
        
        
        //try? mmu.replace(data: romBinary, from: 0x0000)
        mmu.cartridgeRom = romBinary
    }
}

let sampleCount: Double = 100000

// Debugging extensions
extension Gameboy {
    
    func dbgPrintAvgs() {
        // Frequency per second (hertz)
        // The hertz is the reciprocal of seconds or 1/s
        // Something that happens, eg. 4 times every second (or every quarter of a second; 1/4 sec)
        // has a frequency of 1 / 0.25 = 4 hertz.
        // Our values are in nanoseconds (1/1_000_000_000 of a second) so to convert to hertz
        // we divide our value by a second's worth of nanoseconds.
        // eg. a quarter of a second in nanoseconds is 1_000_000_000 / 4 = 250_000_000
        // So if our frequency value was 250_000_000 we could calculate the Hertz:
        // 250_000_000 / 1_000_000_000
        print("-----------------------------------------------")
        print("Debug frequencies (Hz):")
        print("cycle avg: \(1_000_000_000 / cycleAvg)")
        print("cpu avg: \(1_000_000_000 / cpuAvg)")
        print("timer avg: \(1_000_000_000 / timerAvg)")
        print("lcd avg: \(1_000_000_000 / lcdAvg)")
        print("-----------------------------------------------")
        let dbgTimeout = DispatchTime.now() + .seconds(20)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: dbgTimeout, execute: dbgPrintAvgs)
    }
    
    func dbgPrintRegisters() {
      
        print("Registers at \(Date()):")
        cpu.debugRegisters()
        print("-----------------------")
        let dbgTimeout = DispatchTime.now() + .seconds(20)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: dbgTimeout, execute: dbgPrintRegisters)
    }
    
    func dbgCalcAvgTime(timeDiff: Double, for average: Double) -> Double {
        var avg = average
        avg -= avg / sampleCount
        avg += timeDiff / sampleCount
        return avg
    }
}
