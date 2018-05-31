//
//  memory.swift
//  GameBoy
//
//  Created by Teo Sartori on 31/05/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

protocol MEMORY {
    
    init(size: UInt16)
    func read8(at location: UInt16) -> UInt8
    func read16(at location: UInt16) -> UInt16
    mutating func write(at location: UInt16, with value: UInt8)
    
    // Helper function - might be useful for DMA
    //func insert(data: [UInt8], at address: UInt16)
    func replace(data: [UInt8], from address: UInt16) throws
}
