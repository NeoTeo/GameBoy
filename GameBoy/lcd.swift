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
    
    func set(bit: UInt8, on register: MmuRegister)
    
    func unsafeRead8(at location: UInt16) throws -> UInt8
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
    
    var tickModulo: Int
    var ticks: Int
    
    let tileRamStart: UInt16 = 0x8000
    

    // Each byte contains the data of two pixels
    var pixelCount: Int
    
    // Our video buffer uses a byte per pixel
    var vbuf: [UInt8]
    
    let hResolution = 160
    let vResolution = 144
    let verticalLines = 144
    let vBlankLines = 10
    let oamTicks = 20
    let pixelTransferTicks = 43
    let hBlankTicks = 51
    
    lazy var horizontalTicks = oamTicks + pixelTransferTicks + hBlankTicks
    lazy var verticalTicks = verticalLines + vBlankLines
    lazy var lcdModulo = horizontalTicks * verticalTicks
    lazy var lineClockModulo = horizontalTicks
    lazy var lineClock: Int = lineClockModulo
    
    lazy var pxfer = oamTicks + pixelTransferTicks
    lazy var hBlank = oamTicks + pixelTransferTicks + hBlankTicks
    lazy var drawingModulo = verticalLines * horizontalTicks
    lazy var lcdTicks = lcdModulo
    
    var lastVsyncNanos: UInt64 = 0
    var counter = 0
    
    enum LcdStatusBit : UInt8 {
        case lyclySame = 2
        case hblankIrq = 3
        case vblankIrq = 4
        case oamIrq = 5
        case lyclyIrq = 6
    }
    enum LcdMode : UInt8 {
        typealias RawValue = UInt8
        
        case hBlank = 0x00
        case vBlank = 0x01
        case oam =    0x02
        case pxxfer = 0x03
    }

    // FIXME: Needs to get the value from ram not just locally because other parts of
    // the system can set the bits 3 to 6
    var lcdMode: LcdMode {
        didSet {
            var stat = delegateMmu.getValue(for: .stat)
            stat = (stat & 0xFC) | lcdMode.rawValue
            delegateMmu.set(value: stat, on: .stat)
        }
    }

    init(sysClock: Double) {
        // Given a system clock of 4194304 and
        // 4194304 / 70224 = 59,7 (~60 hz)
        // calculate divisor
//        let ramClock: Double = 1048576
        let screenClocks: Double = 17556
//        let rate = screenClocks * (sysClock / ramClock)
        
        pixelCount = hResolution * vResolution
        
        // A bodge to simulate a 60 Hz v-blank signal
//        tickModulo = Int((sysClock / rate).rounded())
//        let tickTimeMillis: Double = 1000 / 1_048_576
//        let refreshInMillis: Double = 1000 / 60
//        let ticksPerRefresh = Int(refreshInMillis / tickTimeMillis)
        tickModulo = Int(screenClocks) //ticksPerRefresh//Int((sysClock / rate).rounded())
        ticks = tickModulo
        lcdMode = .hBlank
        
        vbuf = Array<UInt8>(repeating: 0, count: pixelCount)
    }
    
    func refresh(count: Int) {
        
        // Early out if lcd is off
        guard let lcdc = delegateMmu?.getValue(for: .lcdc), isSet(bit: 7, in: lcdc) else { return }

        // The lcd operation can be split into two main states; the drawing and the vblank
        // Those two states occur within the number of clocks it takes per screen refresh.
        // When in the drawing state the lcd can be in either oam, pxxfer or hBlank mode
        // When in the vblank state it is in vBlank mode.
        
        let stat = delegateMmu.getValue(for: .stat)
        var refresh = false
        
        lcdTicks -= count
        if lcdTicks <= 0 {
            lcdTicks += lcdModulo
            refresh = true
        }
        
        // Drawing state
        // The drawing state goes through 144 lines each of which is 114 clocks
        // and is subdivided into three modes.
        // The OAM mode in the first 20 clocks, the pixel transfer mode
        // in the subsequent 43 clocks and finally the horizontal blank for the
        // last 51 clocks.
        // Determine which mode we're in.
        lineClock -= count
        if lineClock <= 0 {
            
            /* Debug output
            let nowNanos = DispatchTime.now().uptimeNanoseconds
            let deltaMillis = Double(nowNanos - lastVsyncNanos) / 1000000.0
            lastVsyncNanos = nowNanos
            counter = counter &+ 1
            if (counter & 0xFFF) == 0 { print("lineclock: \(deltaMillis) ms") }
            */
            lineClock += lineClockModulo
            
            // Increment ly
            var ly = delegateMmu.getValue(for: .ly)
            ly = (ly + 1) % UInt8(verticalTicks)
            delegateMmu?.set(value: ly, on: .ly)
            
            let lyc = delegateMmu.getValue(for: .lyc)
            if ly == lyc {
                // Check if we need to trigger an interrupt
                if isSet(bit: LcdStatusBit.lyclyIrq.rawValue, in: stat) {
                    delegateMmu.set(bit: mmuInterruptBit.lcdStat.rawValue , on: .ir)
                }
                
                // Set the coincidence bit on
                let newStat = GameBoy.set(bit: LcdStatusBit.lyclySame.rawValue, in: stat)
                delegateMmu.set(value: newStat, on: .stat)
            }
        }
        
        // FIXME: Need to ensure we only enable interrupt bits once per mode change.
        if lcdTicks < (lcdModulo - drawingModulo) {
            
            if lcdMode != .vBlank {
                // V-blank state
                lcdMode = .vBlank
                
                // Set the v-blank interrupt request (regardless of the stat version)
                // They trigger different vblank vectors.
                delegateMmu.set(bit: mmuInterruptBit.vblank.rawValue , on: .ir)
                
                if isSet(bit: LcdStatusBit.vblankIrq.rawValue, in: stat) {
                    delegateMmu.set(bit: mmuInterruptBit.lcdStat.rawValue , on: .ir)
                }
            }

        } else {
            
            // check if we've gone into oam mode
            let modeCount = lineClockModulo - lineClock
            
            if lcdMode != .oam && 0 ..< oamTicks ~= modeCount {
                lcdMode = .oam
                if isSet(bit: LcdStatusBit.oamIrq.rawValue, in: stat) {
                    delegateMmu.set(bit: mmuInterruptBit.lcdStat.rawValue , on: .ir)
                }
            }
            if lcdMode != .pxxfer && oamTicks ..< pxfer ~= modeCount { lcdMode = .pxxfer }
            if lcdMode != .hBlank && pxfer ..< hBlank ~= modeCount {
                lcdMode = .hBlank
                if isSet(bit: LcdStatusBit.hblankIrq.rawValue, in: stat) {
                    delegateMmu.set(bit: mmuInterruptBit.lcdStat.rawValue , on: .ir)
                }
            }
        }

        if refresh == true {
            // Check which area of tile map ram is selected
            let bgTileRamStart: UInt16 = isSet(bit: 3, in: lcdc) ? 0x9C00 : 0x9800

            generateDisplay(from: bgTileRamStart)
        }
    }
    
    func generateDisplay(from vRamLocation: UInt16) {

        let scx = delegateMmu.getValue(for: .scx)
        let scy = delegateMmu.getValue(for: .scy)
        
        do {
//            let preDisplayNanos = DispatchTime.now().uptimeNanoseconds
            
            // Each byte in the background tile ram contains a character code
            // What gets displayed is determined by the scx and scy which define the position of the view.
            // The background consists of an area of 32*32 tiles each of which is 8*8 pixels so
            // the whole background is 256*256 pixels.
            // Calculate which area of the bg we are displaying
            // The tile row and column are scy / 8 and scx / 8
            
            for pixRow in 0 ..< vResolution {
                for pixCol in 0 ..< hResolution {
                    
                    // wrap left/top when overflowing past right/bottom
                    let x = UInt8((pixCol + Int(scx)) & 0xFF)
                    let y = UInt8((pixRow + Int(scy)) & 0xFF)
                    
                    let pixelValue: UInt8 = try pixelForCoord(x: x, y: y, at: vRamLocation)
                    
                    vbuf[pixRow * hResolution + pixCol] = pixelValue
                }
            }
            delegateDisplay?.didUpdate(buffer: vbuf)
            
            /*
             // Debug timing output
             let displayDeltaMillis = Double(DispatchTime.now().uptimeNanoseconds - preDisplayNanos) / 1000000
             counter = counter &+ 1
             if (counter & 0xF) == 0 { print("display time: \(displayDeltaMillis) ms") }
             */

        } catch {
            print("Lcd refresh error \(error)")
        }
    }
    
    // TODO: clean up
    var charData: UInt8 = 0
    var tileRowHi: UInt8 = 0
    var tileRowLo: UInt8 = 0
    
    var prevC: UInt8 = 255
    var prevR: UInt8 = 255
    var prevY: UInt8 = 255
    
    // Returns a pixel value for any coordinate in the bg map as mapped through tile map
    func pixelForCoord(x: UInt8, y: UInt8, at tileBase: UInt16) throws -> UInt8 {
        let bgTileRamStart: UInt16 = tileBase
        
        // Convert coords to col and rows in tile map
        let col = (x >> 3)
        let row = (y >> 3)
        var update = false
        
        // read the byte at the location
        if col != prevC || row != prevR {
            charData = try delegateMmu.unsafeRead8(at: bgTileRamStart + (UInt16(row) << 5) + UInt16(col))
            prevC = col
            prevR = row
            update = true
        }
        // go through the tile data at the given index in tile memory
        // Each 2 bytes in tile memory correspond to a row of 8 pixels
        // So each tile is 16 bytes
        // Mask out three lower bits (same as y % 8) to get the row within the tile
//        let subY = row > 0 ? (y & 7) << 1 : 0
        
        // To calculate which row within the tile to start from we calc the remainder
        // from dividing by 8 and then multiply by two because each tile row is two bytes.
        if prevY != y || update == true {
        let subY = (y & 7) << 1
        
        let tileOffset = tileRamStart + (UInt16(charData) << 4)
        
//        let tileRowHi = try delegateMmu.read8(at: tileOffset + UInt16(subY))
//        let tileRowLo = try delegateMmu.read8(at: tileOffset + UInt16(subY+1))
        tileRowHi = try delegateMmu.unsafeRead8(at: tileOffset + UInt16(subY))
        tileRowLo = try delegateMmu.unsafeRead8(at: tileOffset + UInt16(subY+1))
            
            prevY = y
        }
        // Mask out lower 3 bits (same as x % 8) to get to the column within the tile.
//        let subX = col > 0 ? 7 - (x & 7) : 7
        let subX = 7 - (x & 7)
        
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
