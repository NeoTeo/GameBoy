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
    func read8(at location: UInt16) throws -> UInt8
}

protocol LcdDisplayDelegate {
    func didUpdate(buffer: [UInt8])
}
/*
       <--+ 20 clocks +-> <--------+ 43 clocks +---------> <---------+ 51 clocks +--------->
       |------------------|--------------------------------|---------------------------------+
 ^     |                  |                                |                                 |
 |     |                  |                                |                                 |
 |     |                  |                                |                                 |
 |     |                  |                                |                                 |
 |     |                  |                                |                                 |
 +     |                  |                                |                                 |
 144   |                  |                                |                                 |
 lines |                  |                                |                                 |
 +     |      OAM         |                                |                                 |
 |     |      Search      |       Pixel Transfer           |              H-Blank            |
 |     |                  |                                |                                 |
 |     |                  |                                |                                 |
 |     |                  |                                |                                 |
 |     |                  |                                |                                 |
 |     |                  |                                |                                 |
 |     |                  |                                |                                 |
 |     |                  |                                |                                 |
 |     |                  |                                |                                 |
 |     |                  |                                |                                 |
 v     |                  |                                |                                 |
       +-------------------------------------------------------------------------------------+
 10    |                                     V-Blank                                         |
 lines +-------------------------------------------------------------------------------------+
 
 The clocks above are at RAM clock speed which is 1/4 of the system clock of 4_194_304.
 That's 4194304 / 4 = 1048576
 So if we have 154 lines * 114 clocks = 17556 clocks per screen (at 1/4 max clock speed)
 and 17556 clocks per screen * 4 = 70224 clocks per screen at max clock speed.
 and a refresh rate of 4194304 / 70224 = 59,7
 */
class LCD {
    // keep a reference to the mmu where we have registers mapped to I/O
    var delegateMmu: LcdDelegate!
    var delegateDisplay: LcdDisplayDelegate?
    
//    var dbgTimer: Timer?
    var tickModulo: Int
    var ticks: Int
    
    let tileRamStart: UInt16 = 0x8000
    // Each byte contains the data of two pixels
    let pixelCount = 160 * 144
    // Our video buffer uses a byte per pixel
    var vbuf: [UInt8]

    
    init(sysClock: Double) {
        // Given a system clock of 4194304 and
        // 4194304 / 70224 = 59,7 (~60 hz)
        // calculate divisor
        let ramClock: Double = 1048576
        let screenClocks: Double = 17556
        let rate = screenClocks * (sysClock / ramClock)
        
        // A bodge to simulate a 60 Hz v-blank signal
        tickModulo = Int((sysClock / rate).rounded())
        ticks = tickModulo
        
         vbuf = Array<UInt8>(repeating: 0, count: pixelCount)
    }
    
    func refresh() {
        
        ticks -= 1
        if ticks == 0 {
            ticks = tickModulo

            // Early out if lcd is off
            guard let lcdc = delegateMmu?.getValue(for: .lcdc), isSet(bit: 7, in: lcdc) else { return }
            let scx = delegateMmu.getValue(for: .scx)
            let scy = delegateMmu.getValue(for: .scy)
            
            // do stuff
            delegateMmu?.set(value: 0x90, on: .ly)
            
            do {
                // Bodge to update display
                // Eg. we build a new display buffer here and pass it on. Gotta be a better way.
                
                // Check which area of tile map ram is selected
                let bgTileRamStart: UInt16 = isSet(bit: 3, in: lcdc) ? 0x9C00 : 0x9800

                /*
                // Each byte in the background tile ram contains a character code
                // What gets displayed is determined by the scx and scy which define the position of the view.
                // The background consists of an area of 32*32 tiles each of which is 8*8 pixels so
                // the whole background is 256*256 pixels.
                // Calculate which area of the bg we are displaying
                // The tile row and column are scy / 8 and scx / 8
                let row = scy / 8
                let col = scx / 8
                // The offset from the tile ram would be row * 32 + col
                // Eg if the scy was 0x2A and scx was 0x1F then the offset from 0x9800 would be
                // (0x2A / 8) * 32 + (0x1f / 8) = 0x05 * 32 + 0x03 = 0xA3
                var index = 0

                // FIXME: This needs to wrap
                for r in row ..< row &+ 20 {
                    for c in col ..< col &+ 18 {
                        // read the byte at the location
                        let charData = try delegateMmu.read8(at: bgTileRamStart + (UInt16(r) << 5) + UInt16(c))
                        
                        // go through the tile data at the given index in tile memory
                        // Each 2 bytes in tile memory correspond to a row of 8 pixels
                        // So each tile is 16 bytes
                        let tileOffset = tileRamStart + (UInt16(charData) << 4)
                        for tr in stride(from: 0, to: 16, by: 2) {
                            let tileRowHi = try delegateMmu.read8(at: tileOffset + UInt16(tr))
                            let tileRowLo = try delegateMmu.read8(at: tileOffset + UInt16(tr+1))
                            
                            // Each pixel value is an index into a 4 color clut
                            // Each bit in each of the hi and lo bytes constitute a pixel
                            for bitPos in 0 ..< 8 {

//                                let pixIdx = (((tileRowHi >> bitPos) & 0x01) << 1) + ((tileRowLo >> bitPos) & 0x01)
                                let pixIdx = ((tileRowHi >> bitPos) & 0x02) + ((tileRowLo >> bitPos) & 0x01)
                                
                                // place this value in the buffer we are going to display
                                // calc screen coords
                                let y =
                                vbuf[index] = pixIdx
                                index += 1
                            }
                        }
                    }
                }
 */
                for pixRow in 0 ..< 144 {
                    for pixCol in 0 ..< 160 {

                        // wrap left/top when overflowing past right/bottom
                        let x = UInt8((pixCol + Int(scx)) & 0xFF)
                        let y = UInt8((pixRow + Int(scy)) & 0xFF)
                        
                        let pixelValue = try pixelForCoord(x: x, y: y, at: bgTileRamStart)
                        
                        vbuf[pixRow * 160 + pixCol] = pixelValue
                    }
                }
                delegateDisplay?.didUpdate(buffer: vbuf)
                
            } catch {
                print("Lcd refresh error \(error)")
            }
        }
    }
    
    // Returns a pixel value for any coordinate in the bg map as mapped through tile map
    func pixelForCoord(x: UInt8, y: UInt8, at tileBase: UInt16) throws -> UInt8 {
        let bgTileRamStart: UInt16 = tileBase
        
        // Convert coords to col and rows in tile map
        let col = (x >> 3)
        let row = (y >> 3)
        
        // read the byte at the location
        let charData = try delegateMmu.read8(at: bgTileRamStart + (UInt16(row) << 5) + UInt16(col))
        
        // go through the tile data at the given index in tile memory
        // Each 2 bytes in tile memory correspond to a row of 8 pixels
        // So each tile is 16 bytes
        // Mask out three lower bits (same as y % 8) to get the row within the tile
        let subY = row > 0 ? (y & 7) << 1 : 0
        
        let tileOffset = tileRamStart + (UInt16(charData) << 4)
        
        let tileRowHi = try delegateMmu.read8(at: tileOffset + UInt16(subY))
        let tileRowLo = try delegateMmu.read8(at: tileOffset + UInt16(subY+1))
            
        // Mask out lower 3 bits (same as x % 8) to get to the column within the tile.
        let subX = col > 0 ? 7 - (x & 7) : 7
        
        // Each bit in each of the hi and lo bytes constitute a pixel whose
        // color value (0 to 3) is an index into a 4 colour CLUT.
        // Mask out and join the appropriate column.
        /*
         +----------------------------+
         | location | data | binary   |
         |----------------------------|     +--------+
         | 0x8190   | 0x3C | 00111100 |+--->|  xxxx  |
         | 0x8191   | 0x00 | 00000000 |+ +->| x    x |
         |          |      |          |  |  |        |
         | 0x8192   | 0x42 | 01000010 |+ |  |        |
         | 0x8193   | 0x00 | 00000000 |+-+  .        .
         |          |      |          |     .        .
         | 0x8194   |  .   |    .     |     .        .
         |   .      |  .   |    .     |
         */
        let pixIdx = (((tileRowHi >> subX) & 0x01) << 1) + ((tileRowLo >> subX) & 0x01)
        
        return pixIdx
    }
    
    func start() {
    }
    
    func stop() {
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
                if let lyVal = delegateMmu?.getValue(for: .ly), lyVal >= UInt8(0x90) {
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
