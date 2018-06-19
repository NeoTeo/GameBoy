//
//  Timer.swift
//  GameBoy
//
//  Created by teo on 15/06/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

class Timer {
    
    var clockRate: Double = 0
    var running: Bool = false
    
    // Timer
    var TIMA: UInt8 = 0
    
    // Modulo register of TIMA.
    // When TIMA overflows, the TMA data is loaded into TIMA.
    var TMA: UInt8 = 0
    
    // Timer input clock
    // Bits 0 and 1 are the input clock select
    // 00: f/2^10 = 4096 KHz
    // 01: f/2^4 = 262144 KHz
    // 10: f/2^6 = 65536 KHz
    // 11: f/2^8 = 16384 KHz
    //
    // Bit 3 is Timer Stop
    // 0: Stop timer
    // 1: Start Timer
    var TAC: UInt8 = 0
    
    var timeoutCallback: (()->Void)?
    
    func setClock(hertz: UInt16) {
        clockRate = Double(1 / hertz)
    }
    
    func start(with callback: @escaping ()->Void ) {
        timeoutCallback = callback
        running = true
        tick()
    }
    
    func stop() {
        running = false
    }
    
    func tick() {

        guard running == true else { return }
        
        let startTime = DispatchTime.now()
        // do the work here
        timeoutCallback?()
        let endTime = DispatchTime.now()
        
        let elapsed = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let clockInNs = clockRate * 1_000_000_000
        
        let interval = Int(max(clockInNs - Double(elapsed), 0))
        
        let nextTick = DispatchTime.now() + .nanoseconds(interval)
        
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: nextTick, execute: tick)
    }
}
