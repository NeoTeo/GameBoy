//
//  Timer.swift
//  GameBoy
//
//  Created by teo on 15/06/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

protocol TimerDelegate {
    func set(value: UInt8, on register: MmuRegister)
    func getValue(for register: MmuRegister) -> UInt8
}

class Timer {
    
    var delegateMmu: TimerDelegate!
    
    // Timer. All registers are memory mapped by the MMU.
    var DIV: UInt8 {     // divider register incremented at a rate of (f/2^8 = 16384Hz)
        get { return delegateMmu.getValue(for: .div) }
        set { delegateMmu.set(value: newValue, on: .div) }
    }
    
    var TIMA: UInt8 {     // timer counter r/w incremented at frequency specified in TAC
        get { return delegateMmu.getValue(for: .tima) }
        set { delegateMmu.set(value: newValue, on: .tima) }
    }

    // Modulo register of TIMA.
    // When TIMA overflows, the TMA data is loaded into TIMA.
    var TMA: UInt8 {
        get { return delegateMmu.getValue(for: .tma) }
        set { delegateMmu.set(value: newValue, on: .tma) }
    }
    
    // Timer input clock
    // Bits 0 and 1 are the input clock select
    // 00: f/2^10 = 4096 Hz
    // 01: f/2^4 = 262144 Hz
    // 10: f/2^6 = 65536 Hz
    // 11: f/2^8 = 16384 Hz
    //
    // Bit 3 is Timer Stop
    // 0: Stop timer
    // 1: Start Timer
    var TAC: UInt8 {
        get { return delegateMmu.getValue(for: .tac) }
        set { delegateMmu.set(value: newValue, on: .tac) }
    }
    
    let systemClock: Double
    var tickModulo: Int = 0
    var ticks: Int = 1
    
    var divTickModulo: Int
    var divTicks: Int
    
    init(sysClock: Double) {
        systemClock = sysClock
        
        divTickModulo = Int(systemClock / 16384)
        divTicks = divTickModulo
    }
    
    func selectClock(rate: UInt8) {
        TAC = TAC | (rate & 3)
        tickModulo = calcTickModulo(from: TAC)
        ticks = tickModulo
    }

    func tick() {
    
        // Always increment the div timer. It has a fixed rate of 16384 Hz
        divTicks -= 1
        if divTicks == 0 {
            divTicks = divTickModulo
            DIV = DIV &+ 1
        }

        ticks = (ticks - 1)
        guard ticks == 0 else { return }
        
        ticks = tickModulo
        // increment the TIMA register
        TIMA = TIMA &+ 1
        if TIMA == 0 {
            // fire interrupt by setting bit 2 in IF register (0xFF0F)
            TIMA = TMA
            var irReg = delegateMmu.getValue(for: .ir)
            irReg = GameBoy.set(bit: 2, in: irReg)
            delegateMmu?.set(value: irReg, on: .ir)
        }
        
    }
}

// Called by the MMU
extension Timer : MmuDelegate {
    
    func set(value: UInt8, on register: MmuRegister) {
        switch register {
        case .div:
            // reset to 0 regardless of value
            DIV = 0
        case .tac:
            TAC = value
            // If clock select changed, recalculate tick modulo
            tickModulo = calcTickModulo(from: value)
            
        case .tima:
            TIMA = value
        case .tma:
            TMA = value
            
        default:
            print("Timer error: unsupported register")
        }
    }
    
}

// Utility methods
extension Timer {
    
    // Calculate the number of timer ticks to system ticks.
    // Eg if the system clock is 4194304 then a clock select of 00
    // will need 4194304 / 4096 = 1024 system ticks to one timer tick.
    func calcTickModulo(from clockSelect: UInt8) -> Int {
        switch (clockSelect & 0x3) {
        case 0x00: return Int(systemClock / 4096) // f/2^10 = 4096
        case 0x01: return Int(systemClock / 262144)   // f/2^4 = 262144
        case 0x10: return Int(systemClock / 65536)   // f/2^6 = 65536
        case 0x11: return Int(systemClock / 16384)  // f/2^8 = 16384
        default: return 0
        }
    }
}
