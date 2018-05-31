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
        bodgeBootLoader()
        
        RunLoop.current.add(clockTimer, forMode: .defaultRunLoopMode)
    }
    
    func runCycle(timer: Timer) {
        cpu.clockTick()
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
