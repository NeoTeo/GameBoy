//
//  AppDelegate.swift
//  GameBoy
//
//  Created by Teo Sartori on 22/10/2016.
//  Copyright © 2016 Matteo Sartori. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        do {
            let lcdDisplayController = DmgDisplayController()
            window.contentViewController = lcdDisplayController
            
            // Insert code here to initialize your application
            let gb = try Gameboy(clock: 1_048_576)
            gb.lcd.delegateDisplay = lcdDisplayController
            gb.start()
            
        } catch {
            print("Failed to init Gameboy system: \(error)")
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}

class DmgDisplayController : NSViewController, LcdDisplayDelegate {
    
    var dmgDisplayView: DmgDisplay!
    
    override func loadView() {
        dmgDisplayView = DmgDisplay(frame: NSRect(x: 0, y: 0, width: 160, height: 144))
        self.view = dmgDisplayView
    }
    
    func didUpdate(buffer: [UInt8]) {
        
        dmgDisplayView?.updateView(buffer: buffer)
        DispatchQueue.main.async {
            self.view.needsDisplay = true
        }
        
    }
    
}

class DmgDisplay : NSView {
    
//    var pixelBuf: [UInt8]!
    var pixelBuf: [Int] = [Int]()
    
    
    // DMG pixel colors
    let pixelColors = [[255, 15, 56, 15], [255, 48, 98, 49], [255, 139, 172,15], [255, 155, 188, 15]]
    let pColors: [[UInt8]] = [[255, 15, 56, 15], [255, 48, 98, 49], [255, 139, 172,15], [255, 155, 188, 15]]

//    let height = 144
//    let width = 160
//    let argb = CGColorSpaceCreateDeviceRGB()
//    let context: CGContext?
//
//    init() {
//        let bpr = width * 4
//        let bpp = 4 * 8
//
//        context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bpp, bytesPerRow: bpr, space: argb, bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
//
//    }
//    
//    required init?(coder decoder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
    
    func updateView(buffer: [UInt8]) {
       var pBuf = [UInt8]()
        let height = 144
        let width = 160
        for y in 0 ..< height {
            for x in 0 ..< width {
                let pixVal = buffer[y * width + x]
                pBuf += pColors[Int(pixVal)]
            }
        }
        let bpr = width * 4
        let bpp = 4 * 8

        let provider = CGDataProvider(data: Data(pBuf) as NSData)
        let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: bpp, bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue), provider: provider!, decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent)

        DispatchQueue.main.async {
            self.window?.contentView?.wantsLayer = true
            self.window?.contentView?.layer?.contents = cgImage
    }
//    }
//    func updateView(buffer: [UInt8]) {
//
//        guard let context = context else { return }
//
//        var pBuf = context.data
//        let pitch = context.bytesPerRow
//        var buf = buffer
//        for y in 0 ..< height {
//            for x in 0 ..< width {
//                let pixVal = buffer[y * width + x]
//
//                let uint8arse = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
//                uint8arse.initialize(from: buf, count: 4)
//                pBuf = uint8arse
////                pBuf =
//                    //<UInt8>(pColors[Int(pixVal)])
//            }
//        }
    
        
//        let provider = CGDataProvider(data: Data(pBuf) as NSData)
//        let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: bpp, bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue), provider: provider!, decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent)
//
//        DispatchQueue.main.async {
//            self.window?.contentView?.wantsLayer = true
//            self.window?.contentView?.layer?.contents = cgImage
//        }
    }
    
    /*
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard pixelBuf != nil else { return }
        
        let rep = NSBitmapImageRep(focusedViewRect: dirtyRect)
        
        guard let h = rep?.pixelsHigh, let w = rep?.pixelsWide else {
            return
        }
        
        for y in 0 ..< h {
            for x in 0 ..< w {
                let pixVal = pixelBuf[y * w + x]
                var pixel = pixelColors[Int(pixVal)]
                rep?.setPixel(UnsafeMutablePointer<Int>(&pixel) , atX: x, y: y)
            }
        }
        
        rep?.draw(in: dirtyRect)
    }
 */
}

// global helper stuff
func dbC(_ decimal: Int) {
    print("\(decimal)d, \(String(decimal, radix: 16))h, \(String(decimal, radix:2))b")
    
}
