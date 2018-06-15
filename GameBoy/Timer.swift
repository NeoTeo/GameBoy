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
