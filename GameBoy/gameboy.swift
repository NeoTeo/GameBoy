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
    var timer: DMGTimer
    var controller: Controller
    
    var systemClock: Double
    var clockRate: Double
    
    let romsPath = "/Users/teo/emulation/roms/"
    
    init(clock: Double) throws {
        
        clockRate = 0
        systemClock = clock
        hardwareClockMillis = 1000 / systemClock
        


        cpu = CPU(sysClock: systemClock)
        
        mmu = try DmgMmu(size: 0x10000)

        lcd = LCD(sysClock: systemClock)
        
        controller = Controller()
        controller.delegateMmu = mmu
        
        // Connect lcd and mmu
        lcd.delegateMmu = mmu
        mmu.delegateLcd = lcd
        // Connect the cpu with the memory
        cpu.mmu = mmu
        
        // Make a timer
        timer = DMGTimer(sysClock: systemClock)
        timer.delegateMmu = mmu
        cpu.timer = timer
        mmu.delegateTimer = timer
        mmu.delegateController = controller
        
        cpu.reset()
    }
    
    
    func start() {
        
        if let rom = bodgeRomLoader() {
            mmu.connectCartridge(rom: rom)
        }
        // bodge some code into ram
        bodgeBootLoader()

        clockRate = systemClock //TimeInterval( 1 / systemClock )
        
        // Set the timer clock
        timer.selectClock(rate: 0x00)
        
        allowance = cpuCycleAllowance
        
        // FIXME: debug: single update to refresh the register in the mmu.
        //controller.controllerUpdated()
        
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
    let cpuCycleAllowance: Double = 1000 / 60//240
    let hardwareClockMillis: Double
    var allowance: Double = 0
    var totCycles: UInt64 = 0
    
    
    func runCycle() {
    
        let startTime = DispatchTime.now()
//        var usedCycles: Int = 0
        
        repeat {
            var usedCycles: Int = 0
//            let preCpuTime = DispatchTime.now().uptimeNanoseconds
            // Check the cpu mode and act accordingly
            let mode = cpu.powerMode
            if mode == .normal {
                // A quirk in the DMG hardware means interrupts are disabled until
                // the instruction *after* the IE (0xFB).
                // see https://www.reddit.com/r/EmuDev/comments/7rm8l2/game_boy_vblank_interrupt_confusion/
                let lastOp = cpu.getLastOpcode()
                if lastOp != 0xFB {
                    usedCycles += Int(cpu.interruptHandler())
                }
                usedCycles += Int(cpu.clockTick())
            } else {
                // FIXME: probably not use a single cycle here just to trigger the timer.
                usedCycles = 1
                
                // check if interrupts have occurred to change mode
                if (cpu.mmu.IE & cpu.mmu.IF) != 0 {
                    cpu.powerMode = .normal
                    // FIXME: look into hardware bug mentioned here:
                    // https://www.reddit.com/r/EmuDev/comments/5bfb2t/a_subtlety_about_the_gameboy_z80_halt_instruction/
                    if cpu.IME == true {
                        usedCycles += Int(cpu.interruptHandler())
                    }
                }
            }
            
//            cpuTimeAcc += Double(DispatchTime.now().uptimeNanoseconds - preCpuTime)
            // FIXME: timer and lcd still update when cpu cycle/clock is halted.
            
//            let preTimerTime = DispatchTime.now().uptimeNanoseconds
            // Tick the timer by the number of cycles we used
            timer.tick(count: Int(usedCycles))
//            timerTimeAcc += Double(DispatchTime.now().uptimeNanoseconds - preTimerTime)
            
//            let preLcdTime = DispatchTime.now().uptimeNanoseconds
            // Tick the lcd by the number of cycles we used
            lcd.refresh(count: Int(usedCycles))
//            lcdTimeAcc += Double(DispatchTime.now().uptimeNanoseconds - preLcdTime)
            
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
        let path = romsPath + binaryName
        
        guard FileManager.default.fileExists(atPath: path),
//        guard let path = Bundle.main.path(forResource: binaryName, ofType: nil),
            let bootBinary = try? loadBinary(from: URL(fileURLWithPath: path))
            else {
                print("Failed to load boot binary.")
                return
        }
        
        //try? mmu.replace(data: bootBinary, from: 0x0000)
        mmu.bootRom = bootBinary
    }
    
    func bodgeRomLoader() -> [UInt8]? {

        // passed
//        let binaryName = "mooneye-gb/mem_oam.gb"
//        let binaryName = "mooneye-gb/reg_f.gb"
//        let binaryName = "mooneye-gb/unused_hwio-GS.gb"
//        let binaryName = "mooneye-gb/daa.gb"
//        let binaryName = "mooneye-gb/basic.gb"
//        let binaryName = "mooneye-gb/reg_read.gb"
//        let binaryName = "mooneye-gb/sources-dmgABCmgbS.gb"

//        let binaryName = "cpu_instrs.gb"
//        let binaryName = "11opahl.gb"
//        let binaryName = "10bitops.gb"
//        let binaryName = "09oprr.gb"
//        let binaryName = "08miscinstrs.gb"
//        let binaryName = "07jrjpcallretrst.gb"
//        let binaryName = "06ldrr.gb"
//        let binaryName = "05oprp.gb"
//        let binaryName = "04oprimm.gb"
//        let binaryName = "03opsphl.gb"
//        let binaryName = "02interrupts.gb"
//        let binaryName = "01special.gb" // passes
        
        // Works but has issues
//        let binaryName = "bgbtest.gb"
//        let binaryName = "oam_count_v5.gb"
        
        
        //fail
        let binaryName = "1-lcd_sync.gb"
//        let binaryName = "oam_bug.gb"
        
        // Blargg
//        let binaryName = "Blargg/instr_timing.gb"
        
        // Mooneye
//        let binaryName = "mooneye-gb/intr_1_2_timing-GS.gb"
//        let binaryName = "mooneye-gb/ie_push.gb"
//        let binaryName = "mooneye-gb/add_sp_e_timing.gb"
//        let binaryName = "mooneye-gb/call_timing.gb"
        
        // Playables
//        let binaryName = "games/Tetris.gb"
//        let binaryName = "games/loz.gb"
//        let binaryName = "games/kby.gb"
        
        // Crashers
//        let binaryName = "games/PokemonBlue.gb"
//        let binaryName = "games/drMario.gb"
//        let binaryName = "games/SML.gb"
        
//        guard let path = Bundle.main.path(forResource: binaryName, ofType: nil),
        let path = romsPath + binaryName
    
        guard FileManager.default.fileExists(atPath: path),
            let romBinary = try? loadBinary(from: URL(fileURLWithPath: path))
            else {
                print("Failed to load rom binary.")
                return nil
        }
        
        return romBinary
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
