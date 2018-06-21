//
//  system.swift
//  GameBoy
//
//  Created by Teo Sartori on 31/05/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

protocol SYSTEM {
    var cpu: CPU { get }
    var mmu: MMU { get }
    var clockRate: Double { get }
    
    func start()
}
