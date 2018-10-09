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
    func unsafeRead(bytes: Int, at location: UInt16) -> [UInt8]
    
    func delme()
}

protocol LcdDisplayDelegate {
    func didUpdate(buffer: [UInt8])
}
/*
       <--+ 20 clocks +-> <----+ 43 clocks (minimum) +----> <----+ 51 clocks (maximum) +----->
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
 
 Modes: 0 = H-Blank, 1 = V-Blank, 2 = OAM Search, 3 = Pixel Transfer
 
 * OAM Search is fixed at 20 clocks: 2 cycles per entry in OAM.
 * V-Blank is fixed at 1140 clocks (10 lines * 114 clocks per line)
 * Pixel Transfer is variable but takes at least 43 clocks (2 clocks * 10 sprites)
   The variability comes from "penalties" added to to the base clock of 43:
     Add 2 cycles per sprite on the line
     Add up to (5 cycles @4Mhz) so 5/4 cycles for stopping the background fetcher.
     Add (unconfirmed) up to 2 cycles if the window is visible on the line.
 * H-Blank takes whatever is left to reach 114 clocks (114 - (oam search + pixel transfer))
 
 For now this is just academic. As long as the line takes 114 cycles we're good.
 source: ipfs hash QmNYdV6hSgnKfxXH2BuAwi1xVxKKYUdnvbQw1q7HEGN5WG

 */
class LCD {
    
    // MARK: Constants
    static let hResolution = 160
    static let vResolution = 144
    static let verticalVisibleLines = 144
    static let vBlankLines = 10
    static let oamTicks = 20
    static let pixelTransferTicks = 43
    static let hBlankTicks = 51

    static let horizontalTicks = oamTicks + pixelTransferTicks + hBlankTicks
    static let verticalLines = verticalVisibleLines + vBlankLines
    static let lcdModulo = horizontalTicks * verticalLines
    static let lineClockModulo = horizontalTicks
    static let pxfer = oamTicks + pixelTransferTicks
    static let hBlank = oamTicks + pixelTransferTicks + hBlankTicks
    static let drawingModulo = verticalVisibleLines * horizontalTicks

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

    struct OamEntry {
        let x: UInt8
        let y: UInt8
        let tileNo: UInt8
        let attribute: UInt8
        let line: UInt8
    }
    
    struct TileState {
        var tileNumber: UInt8 = 0
        var tileRowMsb: UInt8 = 0
        var tileRowLsb: UInt8 = 0
        
        var prevC: UInt8 = 255
        var prevR: UInt8 = 255
        var prevY: UInt8 = 255
        var prevMap: UInt16 = 0
    }

    struct LcdState {
        var scanlineClock: Int = 0
        var prevScanlineClock: Int = 0
        var lcdTicks = lcdModulo
    }

    // keep a reference to the mmu where we have registers mapped to I/O
    var delegateMmu: LcdDelegate!
    var delegateDisplay: LcdDisplayDelegate?
    
    var tickModulo: Int
    var ticks: Int
    
    // Each byte contains the data of two pixels
    var pixelCount: Int
    
    // Our video buffer uses a byte per pixel
    var vbuf: [UInt8]
    var activeObjs = [OamEntry]()
    
//    var lastVsyncNanos: UInt64 = 0
//    var counter = 0
    var dbgHblankCount = 0
    var dbgRefreshString = ""

    // The internal state of the LCD.
    var lcdState: LcdState
    
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
        
        pixelCount = LCD.hResolution * LCD.vResolution
        
        // A bodge to simulate a 60 Hz v-blank signal
//        tickModulo = Int((sysClock / rate).rounded())
//        let tickTimeMillis: Double = 1000 / 1_048_576
//        let refreshInMillis: Double = 1000 / 60
//        let ticksPerRefresh = Int(refreshInMillis / tickTimeMillis)
        tickModulo = Int(screenClocks) //ticksPerRefresh//Int((sysClock / rate).rounded())
        ticks = tickModulo
        lcdMode = .hBlank
        
        vbuf = Array<UInt8>(repeating: 0, count: pixelCount)
        
        // Initialize a fresh state.
        lcdState = LcdState()
    }
    
    public func refresh(count: Int) {
        lcdState = self.refresh(count: count, state: lcdState)
    }
    
    // Refresh the LCD screen.
    // count is the number of m-cycles that have passed since last call.
    // All cycles inside refresh() are expressed in m-cycles.
    fileprivate func refresh(count: Int, state: LcdState) -> LcdState {
        
        // Early out if lcd is off
        guard let lcdc = delegateMmu?.getValue(for: .lcdc), isSet(bit: 7, in: lcdc) else { return state }

        var ns = state
        
        // The lcd operation can be split into two main stages; the drawing and the vblank
        // Those two stages occur within the number of clocks it takes per screen refresh.
        // When in the drawing stage the lcd can be in either oam, pxxfer or hBlank mode
        // When in the vblank stage it is in vBlank mode.
        let stat = delegateMmu.getValue(for: .stat)
        
        
        // lcdTicks is the number of clock ticks left in the current frame.
        // Each refresh we subtract from it the number of ticks that have passed.
        ns.lcdTicks -= count
        
        // A frame consists of lcdModulo number of clock ticks, which is 70224/4 = 17556.
        // When the number of ticks in the current frame have run out we add a new frame's worth.
        if ns.lcdTicks <= 0 {
            ns.lcdTicks += LCD.lcdModulo
            dbgRefreshString += "(lcdTicks: \(ns.lcdTicks))\n"
        }
        
        // Drawing state
        // The drawing state goes through 144 lines each of which is 114 clocks
        // and is subdivided into three modes.
        // The OAM mode in the first 20 clocks, the pixel transfer mode
        // in the subsequent 43 clocks and finally the horizontal blank for the
        // last 51 clocks.
        // Determine which mode we're in.
        
        // We use tickCount as a tmp variable to count upwards so it's clearer at
        // what stage the refresh is at. It ranges from 0 to 17555
        // FIXME: Is it a problem that tickCount doesn't go to 17556?
        let tickCount = LCD.lcdModulo - ns.lcdTicks
        
        // Each scanline takes lineClockModulo = 114 number of cycles.
        // Comparing the prevLineClock with the tickCount modulo 114 we can detect
        // a scan line wrap.
        ns.prevScanlineClock = state.scanlineClock
        ns.scanlineClock = tickCount % LCD.lineClockModulo
        
        // Check if we've wrapped which indicates a new scanline
        if ns.prevScanlineClock > ns.scanlineClock {
            // Increment ly
//            print("lineClock: \(lineClock)")
            // Increment LY and wrap if it reaches 154
            var ly = delegateMmu.getValue(for: .ly)
//            ly = (ly + 1) % UInt8(LCD.verticalLines)
            ly = (ly + 1)
            if ly > 154 { ly = 0 }
            delegateMmu?.set(value: ly, on: .ly)
            
            let lyc = delegateMmu.getValue(for: .lyc)
            if ly == lyc {
                // Check if we need to trigger an interrupt
                if isSet(bit: LcdStatusBit.lyclyIrq.rawValue, in: stat) {
                    delegateMmu.set(bit: mmuInterruptBit.lcdStat.rawValue , on: .ir)
                }
                
                // Set the coincidence bit on stat
                let newStat = GameBoy.set(bit: LcdStatusBit.lyclySame.rawValue, in: stat)
                delegateMmu.set(value: newStat, on: .stat)
            } else if isSet(bit: LcdStatusBit.lyclySame.rawValue, in: stat) {
                // Clear the coincidence bit on stat
                let newStat = GameBoy.clear(bit: LcdStatusBit.lyclySame.rawValue, in: stat)
                delegateMmu.set(value: newStat, on: .stat)
            }
            
            // We're done with this scan line so clear sprites list.
            activeObjs = []
        }
        
        let ly = delegateMmu.getValue(for: .ly)
        // FIXME: Need to ensure we only enable interrupt bits once per mode change.
//        if lcdTicks <= (lcdModulo - drawingModulo) {
        if ly > 143 {
//        if ly >= 143 {
        
            if lcdMode != .vBlank {

                guard activeObjs.count == 0 else {
                    fatalError("ffs 2")
                }

                if dbgHblankCount != 144 {
                    print("hblank count is \(dbgHblankCount) at the time of vblank")
                    print(dbgRefreshString)
                }
                dbgHblankCount = 0
                dbgRefreshString = ">VBlank | "

                // V-blank state
                lcdMode = .vBlank
                
                // Set the v-blank interrupt request (regardless of the stat version)
                // They trigger different vblank vectors.
                delegateMmu.set(bit: mmuInterruptBit.vblank.rawValue , on: .ir)
                
                if isSet(bit: LcdStatusBit.vblankIrq.rawValue, in: stat) {
                    delegateMmu.set(bit: mmuInterruptBit.lcdStat.rawValue , on: .ir)
                }
                
                delegateDisplay?.didUpdate(buffer: vbuf)
            }
            
        } else {
            
//            let ly = delegateMmu.getValue(for: .ly)
            
            guard ly < 144 else {
                fatalError("too far")
            }
            // check if we've gone into oam mode
//            let modeCount = lineClockModulo - lineClock
            let modeCount = ns.scanlineClock

            if lcdMode != .oam && 0 ..< LCD.oamTicks ~= modeCount {
                
                if lcdMode == .pxxfer {
                    fatalError("wrong!")
                }
                lcdMode = .oam
                if isSet(bit: LcdStatusBit.oamIrq.rawValue, in: stat) {
                    delegateMmu.set(bit: mmuInterruptBit.lcdStat.rawValue , on: .ir)
                }
    
                // Only compile sprite list if they are enabled.
                if isSet(bit: 1, in: lcdc) {
                    let objHeight: UInt8 = isSet(bit: 2, in: lcdc) ? 16 : 8
                    // OAM search is done on a per-line basis. Find the 10 objs to display.
                    activeObjs = oamSearch(for: ly, objHeight: objHeight)
                }
                dbgRefreshString += "OAM | "
            }
            
            if lcdMode != .pxxfer && LCD.oamTicks ..< LCD.pxfer ~= modeCount {
                lcdMode = .pxxfer
                try! transferPixels(line: ly, activeObjects: activeObjs)
                dbgRefreshString += "Pixel transfer \(modeCount) | "
                
            }
            
            if lcdMode != .hBlank && LCD.pxfer ..< LCD.hBlank ~= modeCount {
                lcdMode = .hBlank
                if isSet(bit: LcdStatusBit.hblankIrq.rawValue, in: stat) {
                    delegateMmu.set(bit: mmuInterruptBit.lcdStat.rawValue , on: .ir)
                }
                
                dbgHblankCount += 1
//                // We're done with this scan line so clear sprites list.
//                activeObjs = []
                dbgRefreshString += "HBlank |\n"
            }

            if lcdMode == .pxxfer {
                dbgRefreshString += "(\(modeCount))"
                if  modeCount >= LCD.pxfer {
                    fatalError("closer?")
                }
            }
        }
        
        return ns
    }
    
    func transferPixels(line: UInt8, activeObjects: [OamEntry]) throws {
        
        // x and y scroll offset
        let scx = delegateMmu.getValue(for: .scx)
        let scy = delegateMmu.getValue(for: .scy)
        
        // Get background palette
        let bgp = delegateMmu.getValue(for: .bgp)
        
        // Get tile data start address
        let lcdc = delegateMmu.getValue(for: .lcdc)
        
        let bgTileRamStart: UInt16 = isSet(bit: 3, in: lcdc) ? 0x9C00 : 0x9800
        let tileDataStart: UInt16 = isSet(bit: 4, in: lcdc) ? 0x8000 : 0x9000
        
        var tileState = TileState()
        
        // FIXME: Do 8 pixels at a time instead.
        for pixCol in 0 ..< LCD.hResolution {
            
            // wrap left/top when overflowing past right/bottom.
            // The display area is 256*256 pixels (32*32 tiles)
            let x = UInt8((pixCol + Int(scx)) & 0xFF)
            let y = UInt8((Int(line) + Int(scy)) & 0xFF)
            
            var pixelValue: UInt8
            (pixelValue, tileState) = try pixelForCoord(x: x, y: y, at: bgTileRamStart, from: tileDataStart, tileState: tileState)
            var shadeVal = (bgp >> (pixelValue << 1)) & 0x3
            
//            if pixCol == 16 && line == 40 {
//                print(pixelValue)
//            }
            // Check if we need to draw a sprite here
            // FIXME: check lcdc obj on flag (bit 1)
            // the screen coords x and y are 0 indexed. The sprites are not,
            // so we adjust.
            
            let sx = UInt8(pixCol+1)
            let sy = UInt8(line+1)
            
            // activeObjs holds any sprites to display
            for obj in activeObjects {

                // Ignore objs that are not overlapping the currently drawn pixel
                guard sx > (Int(obj.x) - 8) && sx <= Int(obj.x) else { continue }
                
                // Calculate the row and column offset within a given tile
                let objHeightMask: UInt8 = isSet(bit: 2, in: lcdc) ? 0xF : 0x7
                let objXFlipped = isSet(bit: 5, in: obj.attribute)
                let objYFlipped = isSet(bit: 6, in: obj.attribute)
                
                // Sprite origin is lower right
                let tileRow = objYFlipped ? (obj.y - sy) << 1 : (15 - (obj.y - sy)) << 1
                let tileCol = objXFlipped ? 7 - (obj.x - sx) : (obj.x - sx)
                
                if obj.tileNo == 0xD4 {
                    print("bug")
                }
//                let offset = isSet(bit: 2, in: lcdc) ? Int(obj.tileNo) & 0xFE : Int(obj.tileNo)
                let offset = Int(obj.tileNo)
                let tileAddress = UInt16(Int(0x8000) + (offset << 4))
                
                let tileRowLsb = try delegateMmu.unsafeRead8(at: tileAddress + UInt16(tileRow))
                let tileRowMsb = try delegateMmu.unsafeRead8(at: tileAddress + UInt16(tileRow+1))
                // Extract the two bits (one from the most significant byte and one from the least)
                // that make a palette index from the two bytes that define a row of 8 pixels.
                let pixIdx = (((tileRowMsb >> tileCol) & 0x01) << 1) + ((tileRowLsb >> tileCol) & 0x01)

                // Skip if transparent pixel
                guard pixIdx != 0 else { continue }
                
                let obp = isSet(bit: 4, in: obj.attribute) ? delegateMmu.getValue(for: .obp1) : delegateMmu.getValue(for: .obp0)
                // Check for priority and decide if we need to overwrite
                
                let shade = (obp >> (pixIdx << 1)) & 0x3
                //guard shade != 0 else { continue }
                shadeVal = shade
            }
            
            vbuf[Int(line) * LCD.hResolution + pixCol] = shadeVal
        }
    }
    
    // Returns a pixel value for any coordinate in the bg map as mapped through tile map
    func pixelForCoord(x: UInt8, y: UInt8, at tileMapStart: UInt16, from tileDataStart: UInt16, tileState: TileState) throws -> (UInt8, TileState) {

        var ts = tileState
        // Convert x, y pixel coords (from 256*256 bg map) into col, row tile coords (32*32)
        // eg. pixels 0 to 7 correspond to map column/row 0, between 8 and 15 -> 1, etc.
        let mapCol = (x >> 3)
        let mapRow = (y >> 3)
        
        // Update flag indicates that we've changed the char data.
        var update = false

        // Read a new byte at the location only if we've changed map or row/column.
        if mapCol != ts.prevC || mapRow != ts.prevR || tileMapStart != ts.prevMap {
            
            // The tile map is 32 by 32 tiles.
            // Since each row is 32 columns, multiply mapRow by 32 to get the row.
            ts.tileNumber = try delegateMmu.unsafeRead8(at: tileMapStart + (UInt16(mapRow) << 5) + UInt16(mapCol))
//            if tileNumber == 0x2A {
//                print("omfg")
//                print("mapCol: \(mapCol), mapRow: \(mapRow)")
//                print("tilemapstart:")
//                dbC(tileMapStart)
//                let addr = tileMapStart + (UInt16(mapRow) << 5) + UInt16(mapCol)
//                print("addr:")
//                dbC(addr)
//                delegateMmu.delme()
//            }

            ts.prevC = mapCol
            ts.prevR = mapRow
            ts.prevMap = tileMapStart
            update = true
        }

        // TODO: find better way of reusing the tileRowMsb/Lsb
        // If we've changed tile row/col or we're reading a different row *within a tile*...
        if ts.prevY != y || update == true {
            // Go through the tile data at the given index in tile memory.
            
            // If the tile data table is located at 0x8800 it is sharing space with the obj tile table
            // and the indexes range from -128 to 127
            let tileNum = tileDataStart == 0x8000 ? Int(ts.tileNumber) : signedVal(from: ts.tileNumber)
            
            // Each 2 bytes in tile memory correspond to a row of 8 pixels,
            // so each 8x8 pixel tile is 16 bytes.
            // A tile's start address is the start address of all tiles' data + (the tile number * the tile size)
            let tileAddress = UInt16(Int(tileDataStart) + (tileNum << 4))
            
            // To calculate which row *within the tile* to start from we only consider
            // values between 0 and 7 and then multiply that by two (each tile row is two bytes).
            let tileRow = (y & 7) << 1

            ts.tileRowLsb = try delegateMmu.unsafeRead8(at: tileAddress + UInt16(tileRow))
            ts.tileRowMsb = try delegateMmu.unsafeRead8(at: tileAddress + UInt16(tileRow+1))
            
//            if (mapCol == 6 || mapCol == 7) && mapRow == 0x11 {
//                print("tile address: ")
//                dbC(tileAddress)
//                print("tile row: \(tileRow)")
//                dbC(UInt16(tileRowLsb))
//                dbC(UInt16(tileRowMsb))
//            }

            ts.prevY = y
        }
        // Mask in lower 3 bits (not same as x % 8) to get to the column within the tile.
        let tileCol = 7 - (x & 7)
        
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
//        let pixIdx = (((tileRowHi >> tileCol) & 0x01) << 1) + ((tileRowLo >> tileCol) & 0x01)
        // Extract the two bits (one from the most significant byte and one from the least)
        // that make a palette index from the two bytes that define a row of 8 pixels.
        let pixIdx = (((ts.tileRowMsb >> tileCol) & 0x01) << 1) + ((ts.tileRowLsb >> tileCol) & 0x01)

        return (pixIdx, ts)
    }
    
    // WIP
    func fetch(row: UInt8, in tile: UInt8) -> (UInt8, UInt8) {
        return (0,0)
    }
    
    // Search for objs (sprites) whose x value is > 0
    func oamSearch(for line: UInt8, objHeight: UInt8) -> [OamEntry] {
        
        var displayObjs = [OamEntry]()
        let oamBaseAddress: Int = 0xFE00
        let oamEntryBytes = 4
        
        // There are a maximum of 8 * 5 objs we need to search
        for objIdx in stride(from:0, to: 8 * 5 * oamEntryBytes, by: oamEntryBytes) {
            let oam = delegateMmu.unsafeRead(bytes: oamEntryBytes, at: UInt16(oamBaseAddress + objIdx))
            // An obj origin is lower right
            // skip objects with an x of 0.
            let scanline = Int(line)
            let objYPos = oam[0]
            let objXPos = oam[1]
            guard objXPos != 0 &&
                ((line &+ 16) >= objYPos) &&
                ((line &+ 16) < (objYPos + objHeight))
//            else { continue }
//            guard oam[1] != 0 &&
////                (scanline >= (Int(oam[0]) - 16)) &&
//                (scanline >= (Int(oam[0] - objHeight))) &&
//                (scanline < oam[0])
            
            else { continue }
            
            displayObjs.append(OamEntry(x: oam[1], y: oam[0], tileNo: oam[2], attribute: oam[3], line: line))
//            print("OAM:")
//            print("x: \(oam[0])")
//            print("y: \(oam[1])")
//            print("Tile no: \(oam[2])")
//            print("Attribute: \(oam[3])")
            
        }
        return displayObjs
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
//            if isSet(bit: 7, in: value) {
//                // Reset ly on toggling lcd on
//                delegateMmu?.set(value: 0, on: .ly)
//                lcdTicks = lcdModulo
//                lineClock = 0
//                dbgRefreshString += "eek"
//            }
            // only reset ly when turning lcd OFF
            if isSet(bit: 7, in: value) == false {
                if lcdMode != .vBlank {
//                    fatalError("disabling lcd outside of vblank.")
                    print("disabling lcd outside of vblank.")
                }
                delegateMmu?.set(value: 0, on: .ly)
            }
            break
            
        case .scy, .scx:
            break
        default:
            return
        }
    }
}

// Debug stuff
extension LCD {
    
    func dbPTileId(for x: UInt8, y: UInt8) {
        // Convert coords to col and rows in tile map
        let mapCol = Int(x >> 3)
        let mapRow = Int(y >> 3)

        let tId = tileId(col: mapCol, row: mapRow)
        print("Tile id for coords \(x),\(y): \(String(describing: tId))")
    }
    
    func dbPBgTileIds() {
        
        for row in 0 ..< 32 {
            
            for col in 0 ..< 32 {
                
                // Each row is 32 columns so to get the row multiply mapRow by 32
                if let charData = tileId(col: col, row: row) {
                    print(String(format: "%02X", charData), terminator: ".")
                }
            }
            print(">")
        }

    }
    
    func tileId(col: Int, row: Int) -> UInt8? {
        let lcdc = delegateMmu.getValue(for: .lcdc)
        let tileMapStart: UInt16 = isSet(bit: 3, in: lcdc) ? 0x9C00 : 0x9800
        // Each row is 32 columns so to get the row multiply mapRow by 32
        return try? delegateMmu.unsafeRead8(at: tileMapStart + (UInt16(row) << 5) + UInt16(col))
    }
}
