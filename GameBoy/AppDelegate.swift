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
    
    // To capture keyboard events
    override var acceptsFirstResponder: Bool { return true }
    override func becomeFirstResponder() -> Bool { return true }
    override func resignFirstResponder() -> Bool { return true }
    
    
    override func loadView() {
        dmgDisplayView = DmgDisplay(frame: NSRect(x: 0, y: 0, width: 160, height: 144))
        self.view = dmgDisplayView
        
        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { (theEvent)-> NSEvent? in
            self.keyUp(with: theEvent)
            return nil
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { (theEvent)-> NSEvent? in
            self.keyDown(with: theEvent)
            return nil
        }
    }
    
    func didUpdate(buffer: [UInt8]) {
        
        dmgDisplayView?.updateView(buffer: buffer)
        DispatchQueue.main.async {
            self.view.needsDisplay = true
        }
    }
    
    override func keyDown(with event: NSEvent) {
        print("ongo")
    }
    
}

class DmgDisplay : NSView {
    
    var pixelBuf: [Int] = [Int]()
    
    
    // DMG pixel colors
    // Every three bytes correspond to the red, green and blue component of a color in the lookup table.
    // There are four colors in total.
    let clut: [UInt8] = [0xE0, 0xF8, 0xD0, 0x34, 0x68, 0x56, 0x88, 0xC8, 0x70, 0x8, 0x18, 0x20]
    
    func updateView(buffer: [UInt8]) {
        
        let height = 144
        let width = 160

        let bpr = width
        let bpp = 8

        guard let testColorSpace = CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(), last: 3, colorTable: UnsafePointer<UInt8>(clut)) else {
            print("Failed to make color space from clut")
            return
        }
        
        let provider = CGDataProvider(data: Data(buffer) as NSData)
        let cgImage = CGImage(width: width,
                              height: height,
                              bitsPerComponent: 8,
                              bitsPerPixel: bpp,
                              bytesPerRow: bpr,
                              space: testColorSpace,
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                              provider: provider!,
                              decode: nil,
                              shouldInterpolate: true,
                              intent: CGColorRenderingIntent.defaultIntent)

        DispatchQueue.main.async {
            self.window?.contentView?.wantsLayer = true
            self.window?.contentView?.layer?.contents = cgImage
        }
    }
}

// global helper stuff
func dbC(_ decimal: UInt16) {
    print("\(decimal)d, \(String(decimal, radix: 16))h, \(String(decimal, radix:2))b")
    
}
