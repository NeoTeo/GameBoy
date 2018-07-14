//
//  controller.swift
//  GameBoy
//
//  Created by Teo Sartori on 14/07/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

protocol ControllerDelegate {
    func set(value: UInt8, on register: MmuRegister)
    func getValue(for register: MmuRegister) -> UInt8
}

class Controller {
 
    var delegateMmu: ControllerDelegate!
    
    // When a change occurs to the controller we write to the delegate mmu
    func controllerUpdated() {
        // TODO: read some actual controller data here
        // 0xCF means nothing is pressed.
        let newValue: UInt8 = 0xCF
        delegateMmu.set(value: newValue, on: .p1)
    }
}

// Called by the MMU
extension Controller : MmuDelegate {
    func set(value: UInt8, on register: MmuRegister) {
        // Sets whether the button keys or the directional keys are selected
        // Whenever the controller detects a change it will write the value for the
        // selected keys into its P1 register.
    }
    
}
