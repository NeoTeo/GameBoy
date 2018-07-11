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
        
        hardwareClockMillis = 1000 / systemClock
        
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
        mmu.delegateTimer = timer
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
        
        allowance = cpuCycleAllowance
        //runCycle(timer: Timer.init())
        runCycle()
        
//        dbgPrintAvgs()
//        dbgPrintRegisters()
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
    
    var accu: UInt64 = 0
    var cnt: UInt64 = 0
    var gtot = [UInt64]()
    
    let cycleQ = DispatchQueue.global(qos: .userInitiated)
    // We want our cycle allowance (time given to each cycle of the emulator) to be calculated from 60 hz
    let emuAllowanceNanos: Double = 1_000_000_000 / 60
    
    // The cycle allowance is the number of cycles we allow the cpu to run for each emulator cycle.
    // A DMG hardware cycle takes 1000 / 1048576 = 0.0009536743164 milliseconds
    // To calculate the time allowance (in milliseconds) for the cpu we divide a by the
    // desired frequency, in this case 240 hertz:
    // 1000 ms / 240 hz = 4.1666666667 milliseconds per emulator cycle.
    // This corresponds to 4.1666666667 / 0.0009536743164 = 4369.0666667303 cycles
    let cpuCycleAllowance: Double = 1000 / 240
    let hardwareClockMillis: Double
    var allowance: Double = 0
    var totCycles: UInt64 = 0
    
    func runCycle() {
        
        let startTime = DispatchTime.now()
        var usedCycles: Int = 0
        
        repeat {
            // Check the cpu mode and act accordingly
            let mode = cpu.powerMode
            if mode == .normal {
                usedCycles = Int(cpu.clockTick())
            } else {
                usedCycles = 1
                // check if interrupts have occurred to change mode
                if (cpu.mmu.IE & cpu.mmu.IF) != 0 {
                    cpu.powerMode = .normal
                    if cpu.IME == false {
                        print("PC should be the one following HALT.")
                    } else {
                        print("PC should be the one of each interrupt starting address...")
                        // Find out which interrupts have been triggered and jump to them.
                    }
                }
            }
            
            // Tick the timer by the number of cycles we used
            timer.tick(count: Int(usedCycles))
            
            // Tick the lcd by the number of cycles we used
            lcd.refresh(count: Int(usedCycles))

            // subtract the time used on the cycles from the cycleAllowance.
            // The DMG hardware has a cycle of systemClock (usually 1_048_576 hertz) so
            // A cycle takes 1000 / 1_048_576 = 0.0009536743164 milliseconds
            allowance -= Double(usedCycles) * hardwareClockMillis
            
            totCycles += UInt64(usedCycles)
        } while allowance > 0

        // reset allowance (adjusting for the now negative allowance)
        allowance = cpuCycleAllowance + allowance

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds)

        accu = accu &+ UInt64(elapsed)
        cnt += 1
        if (accu & 0xFF) == 0 {
            
            gtot.append(accu/cnt)
            let avg = Int(gtot.reduce(0, +)) / gtot.count
            print("Avg: \(avg) nanoseconds")
            accu = 0
            cnt = 0
        }

        //  Subtract the actual time spent from the emulator f. If negative use 0.
        let interval = max(Int(emuAllowanceNanos - elapsed), 0)
    
        let nextCycle = DispatchTime.now() + .nanoseconds(interval)
        
        cycleQ.asyncAfter(deadline: nextCycle, execute: runCycle)
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
//        let binaryName = "03opsphl.gb"
//        let binaryName = "02interrupts.gb"
        let binaryName = "01special.gb" // passes
//        let binaryName = "bgbtest.gb"
//        let binaryName = "Tetris.gb"
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
