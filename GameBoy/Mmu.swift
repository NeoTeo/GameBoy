//
//  Mmu.swift
//  GameBoy
//
//  Created by Teo Sartori on 31/05/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

protocol MMU {
    var size: Int { get }
    var IE: UInt8 { get set }
    var IF: UInt8 { get set }
    
    init(size: Int) throws
    func read8(at location: UInt16) -> UInt8
    func read16(at location: UInt16) -> UInt16
    mutating func write(at location: UInt16, with value: UInt8)
    
    // Helper function - might be useful for DMA
    func setIE(flag: DmgMmu.InterruptFlag)
    func setIF(flag: DmgMmu.InterruptFlag)
    //func insert(data: [UInt8], at address: UInt16)
    func replace(data: [UInt8], from address: UInt16) throws
    func debugPrint(from: UInt16, bytes: UInt16)
}
