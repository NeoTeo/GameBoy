//
//  lcd.swift
//  GameBoy
//
//  Created by Teo Sartori on 18/06/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

protocol LcdDelegate {
    func set(value: UInt8, on register: MmuRegister)
    func getValue(for register: MmuRegister) -> UInt8
}

//enum LcdRegister : UInt8 {
//    case lcdc   // LCD control
//    case stat   // LCD status info
//    case scy    // scroll y register
//    case scx    // scroll x register
//    case ly     // LCD y coordinate (scanline y position) (read only)
//    case lyc    // LY compare register (read/write)
//}

class LCD {
    // keep a reference to the mmu where we have registers mapped to I/O
    var delegate: LcdDelegate?
    
//    var dbgTimer: Timer?
    var tickModulo: Int
    var ticks: Int
    
    init(sysClock: Double) {
        // Bodge a 60 hz
        tickModulo = Int(sysClock / 60)
        ticks = tickModulo
    }
    
    func refresh() {
        
        ticks -= 1
        if ticks == 0 {
            ticks = tickModulo
            
            // do stuff
            delegate?.set(value: 0x90, on: .ly)
        }
    }
    
    func start() {
        
        // debug. Start a timer to fake vsync.
//        dbgTimer = Timer()
//        dbgTimer?.selectClock(rate: 0x01)
//        dbgTimer?.setClock(hertz: 60)
//        dbgTimer?.start {
//
//            // LY holds the vertical position of the scanline. With a resolution of
//            // 240x144 the bottom Y pos is 144 or 0x90
//            self.delegate?.set(value: 0x90, on: .ly)
//        }
    }
    
    func stop() {
//        dbgTimer?.stop()
    }
    
}

// Called by the MMU
extension LCD : MmuDelegate {
    
    func set(value: UInt8, on register: MmuRegister) {
        switch register {
        case .lyc:
            // Do whatever it is this does
            break
            
        case .lcdc: // LCD control
            /*
             FF40 - LCDC - LCD Control (R/W)
             Bit 7 - LCD Display Enable             (0=Off, 1=On)
             Bit 6 - Window Tile Map Display Select (0=9800-9BFF, 1=9C00-9FFF)
             Bit 5 - Window Display Enable          (0=Off, 1=On)
             Bit 4 - BG & Window Tile Data Select   (0=8800-97FF, 1=8000-8FFF)
             Bit 3 - BG Tile Map Display Select     (0=9800-9BFF, 1=9C00-9FFF)
             Bit 2 - OBJ (Sprite) Size              (0=8x8, 1=8x16)
             Bit 1 - OBJ (Sprite) Display Enable    (0=Off, 1=On)
             Bit 0 - BG Display (for CGB see below) (0=Off, 1=On)
             */
            if isSet(bit: 7, in: value) {
                start()
            } else {
                // Only allowed to stop during v-blank.
                if let lyVal = delegate?.getValue(for: .ly), lyVal >= UInt8(0x90) {
                    stop()
                }
            }
            // FIXME: Handle other cases
            
        case .scy: // vertical scroll register
            // perform actual scrolling on the display
            break
        default:
            return
        }
    }
}
