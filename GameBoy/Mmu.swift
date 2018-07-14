//
//  Mmu.swift
//  GameBoy
//
//  Created by Teo Sartori on 31/05/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

protocol MMU : LcdDelegate, TimerDelegate, ControllerDelegate {
    var size: Int { get }
    var IE: UInt8 { get set }
    var IF: UInt8 { get set }
    
    var bootRom: [UInt8] { get set }
    var cartridgeRom: [UInt8]? { get set }
    
    var delegateLcd: MmuDelegate? { get set }
    var delegateTimer: MmuDelegate? { get set }
    var delegateController: MmuDelegate? { get set }
    
    init(size: Int) throws
    func read8(at location: UInt16) throws -> UInt8
    func read16(at location: UInt16) throws -> UInt16
    func write(at location: UInt16, with value: UInt8)
    
    func connectCartridge(rom: [UInt8])
    // Helper function - might be useful for DMA
//    func setIE(flag: mmuInterruptFlag)
//    func setIF(flag: mmuInterruptFlag)
    //func insert(data: [UInt8], at address: UInt16)
    func replace(data: [UInt8], from address: UInt16) throws
//    func debugPrint(from: UInt16, bytes: UInt16)
    func debugPrint(from: UInt16, bytes: UInt16, type: MemoryType)
}

enum MemoryType {
    case bootRom
    case cartRom
    case mainRam
}

// Interrupt MMU functions in order of priority
//enum mmuInterruptFlag : UInt8 {
//    case vblank  = 0
//    case lcdStat = 2
//    case timer   = 4
//    case serial  = 8
//    case joypad  = 16
//}
enum mmuInterruptBit : UInt8 {
    case vblank  = 0
    case lcdStat = 1
    case timer   = 2
    case serial  = 3
    case joypad  = 4
}

// The MMU maps some memory locations to other hardware registers.
// All mapped registers start at 0xFF00 so we only define the last byte
// I/O register mapping (data from GameBoyProgManVer1.1 and http://bgb.bircd.org/pandocs.htm#interrupts)
enum MmuRegister : Int {
    case p1 =   0xFF00      // port P15-P10 (joypad) r/w
    case sb =   0xFF01      // serial transfer register r/w
    case sc =   0xFF02      // serial control r/w
    case div =  0xFF04     // divider
    case tima = 0xFF05    // timer
    case tma =  0xFF06     // timer modulo
    case tac =  0xFF07     // timer control
    case ir =   0xFF0F      // interrupt request
    
    // Sound registers
    // Channel 1 - Tone & Sweep
    case nr10 = 0xFF10    // sweep register r/w
    case nr11 = 0xFF11    // sound length r/w
    case nr12 = 0xFF12    // envelope r/w
    case nr13 = 0xFF13    // channel 1 lower-order frequency w
    case nr14 = 0xFF14    // channel 1 higher-order frequency r/w
    // Channel 2 - Tone
    case nr21 = 0xFF16    // sound length r/w
    case nr22 = 0xFF17    // envelope r/w
    case nr23 = 0xFF18    // lower-order frequency w
    case nr24 = 0xFF19    // higher-order frequency r/w
    // Channel 3 - Wave
    case nr30 = 0xFF1A    // sound off r/w
    case nr31 = 0xFF1B    // sound length r/w
    case nr32 = 0xFF1C    // output level r/w
    case nr33 = 0xFF1D    // lower-order frequency w
    case nr34 = 0xFF1E    // higher-order frequency r/w
    
    // Channel 4 - Noise
    case nr41 = 0xFF20    // sound length r/w
    case nr42 = 0xFF21    // envelope r/w
    case nr43 = 0xFF22    // polynomial counter w
    case nr44 = 0xFF23    // counter r/w
    // Sound control registers
    case nr50 = 0xFF24    // channel control r/w
    case nr51 = 0xFF25    // selection of sound output
    case nr52 = 0xFF26    // sound on/off
    
    case ie =   0xFFFF      // interrupt enable
    
    case lcdc = 0xFF40    // LCD control
    case stat = 0xFF41    // LCD status info
    case scy =  0xFF42     // scroll y register
    case scx =  0xFF43     // scroll x register
    case ly =   0xFF44      // LCD y coordinate (scanline y position) (read only)
    case lyc =  0xFF45     // LY compare register (read/write)
    case dma =  0xFF46     // DMA transfer (write only)
    
    case bgp =  0xFF47     // background palette data
    case obp0 = 0xFF48    // OBJ palette data 0 (read/write)
    case obp1 = 0xFF49    // OBJ palette data 1 (read/write)
    case wy =   0xFF4A      // window y-coordinate
    case wx =   0xFF4B      // window x-coordinate
    
    case romoff = 0xFF50  // disable rom
}
