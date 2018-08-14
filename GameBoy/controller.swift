//
//  controller.swift
//  GameBoy
//
//  Created by Teo Sartori on 14/07/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation
import EventKit

protocol ControllerDelegate {
    func set(value: UInt8, on register: MmuRegister)
    func getValue(for register: MmuRegister) -> UInt8
}

class Controller {
 
    var delegateMmu: ControllerDelegate!
    
    init() {
        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { (theEvent)-> NSEvent? in
            self.keyUp(with: theEvent)
            return nil
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { (theEvent)-> NSEvent? in
            self.keyDown(with: theEvent)
            return nil
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { (theEvent)-> NSEvent? in
            self.shiftHappened(with: theEvent)
            return nil
        }

    }
    
    // Key names
    let leftArrow = 123
    let rightArrow = 124
    let upArrow = 126
    let downArrow = 125
    let keyA = 0
    let keyB = 1
    let keyEnter = 36
    let keyBackslash = 42

    let dirR: UInt8 = 1
    let dirL: UInt8 = 1 << 1
    let dirU: UInt8 = 1 << 2
    let dirD: UInt8 = 1 << 3
    
    let butA: UInt8 = 1
    let butB: UInt8 = 1 << 1
    let butSel: UInt8 = 1 << 2
    let butSta: UInt8 = 1 << 3
    
    var dPadState: UInt8 = 0xFF
    var buttonsState: UInt8 = 0xFF
    
    func shiftHappened(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            print("Oh shift!")
        }
    }
    
    func keyDown(with event: NSEvent) {
        setState(for: Int(event.keyCode), on: true)
    }
    
    func keyUp(with event: NSEvent) {
        setState(for: Int(event.keyCode), on: false)
    }
    
    func setState(for key: Int, on: Bool) {
        var butBit: UInt8?
        var dirBit: UInt8?
        
        switch key {
        case leftArrow:
            dirBit = dirL
        case rightArrow:
            dirBit = dirR
        case upArrow:
            dirBit = dirU
        case downArrow:
            dirBit = dirD
        case keyA:
            butBit = butA
        case keyB:
            butBit = butB
        case keyEnter:
            butBit = butSta
        case keyBackslash:
            butBit = butSel
        
        default:
            print("Invalid key code \(key).")
        }

        if let b = butBit {
            buttonsState = (on == true) ? buttonsState & ~b : buttonsState | b
        } else if let b = dirBit {
            dPadState = (on == true) ? dPadState & ~b : dPadState | b
        }
    }
}

// Called by the MMU
extension Controller : MmuDelegate {
    func set(value: UInt8, on register: MmuRegister) {
        // Sets whether the button keys or the directional keys are selected
        // Whenever the controller detects a change it will write the value for the
        // selected keys into its P1 register.
        //print("changing state \(value)")
        var state = delegateMmu.getValue(for: .p1)
        switch value {
        case 0x10:
            state = (state & 0xF0) | (buttonsState & 0xF)
        case 0x20:
            state = (state & 0xF0) | (dPadState & 0xF)
        default:
            break
        }
        delegateMmu.set(value: state, on: .p1)
    }
}
