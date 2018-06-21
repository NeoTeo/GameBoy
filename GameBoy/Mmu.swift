//
//  Mmu.swift
//  GameBoy
//
//  Created by Teo Sartori on 31/05/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

protocol MMU : LcdDelegate, TimerDelegate {
    var size: Int { get }
    var IE: UInt8 { get set }
    var IF: UInt8 { get set }
    
    var delegateLcd: MmuDelegate? { get set }
    
    init(size: Int) throws
    func read8(at location: UInt16) throws -> UInt8
    func read16(at location: UInt16) -> UInt16
    func write(at location: UInt16, with value: UInt8)
    
    // Helper function - might be useful for DMA
    func setIE(flag: mmuInterruptFlag)
    func setIF(flag: mmuInterruptFlag)
    //func insert(data: [UInt8], at address: UInt16)
    func replace(data: [UInt8], from address: UInt16) throws
    func debugPrint(from: UInt16, bytes: UInt16)
}

// Interrupt MMU functions in order of priority
enum mmuInterruptFlag : UInt8 {
    case vblank  = 0
    case lcdStat = 2
    case timer   = 4
    case serial  = 8
    case joypad  = 16
}

// The MMU maps some memory locations to other hardware registers.
// All mapped registers start at 0xFF00 so we only define the last byte
// I/O register mapping (data from GameBoyProgManVer1.1 and http://bgb.bircd.org/pandocs.htm#interrupts)
enum MmuRegister : UInt8 {
    case p1 = 0x00      // port P15-P10 (joypad) r/w
    case sb = 0x01      // serial transfer register r/w
    case sc = 0x02      // serial control r/w
    case div = 0x04     // divider
    case tima = 0x05    // timer
    case tma = 0x06     // timer modulo
    case tac = 0x07     // timer control
    case ir = 0x0F      // interrupt request
    
    // Sound registers
    // Channel 1 - Tone & Sweep
    case nr10 = 0x10    // sweep register r/w
    case nr11 = 0x11    // sound length r/w
    case nr12 = 0x12    // envelope r/w
    case nr13 = 0x13    // channel 1 lower-order frequency w
    case nr14 = 0x14    // channel 1 higher-order frequency r/w
    // Channel 2 - Tone
    case nr21 = 0x16    // sound length r/w
    case nr22 = 0x17    // envelope r/w
    case nr23 = 0x18    // lower-order frequency w
    case nr24 = 0x19    // higher-order frequency r/w
    // Channel 3 - Wave
    case nr30 = 0x1A    // sound off r/w
    case nr31 = 0x1B    // sound length r/w
    case nr32 = 0x1C    // output level r/w
    case nr33 = 0x1D    // lower-order frequency w
    case nr34 = 0x1E    // higher-order frequency r/w
    // Channel 4 - Noise
    case nr41 = 0x20    // sound length r/w
    case nr42 = 0x21    // envelope r/w
    case nr43 = 0x22    // polynomial counter w
    case nr44 = 0x23    // counter r/w
    // Sound control registers
    case nr50 = 0x24    // channel control r/w
    case nr51 = 0x25    // selection of sound output
    case nr52 = 0x26    // sound on/off
    
    case ie = 0xFF      // interrupt enable
    
    case lcdc = 0x40    // LCD control
    case stat = 0x41    // LCD status info
    case scy = 0x42     // scroll y register
    case scx = 0x43     // scroll x register
    case ly = 0x44      // LCD y coordinate (scanline y position) (read only)
    case lyc = 0x45     // LY compare register (read/write)
    case dma = 0x46     // DMA transfer (write only)
    
    case bgp = 0x47     // background palette data
    case obp0 = 0x48    // OBJ palette data 0 (read/write)
    case obp1 = 0x49    // OBJ palette data 1 (read/write)
    case wy = 0x4A      // window y-coordinate
    case wx = 0x4B      // window x-coordinate
    
    case romoff = 0x50  // disable rom
}
