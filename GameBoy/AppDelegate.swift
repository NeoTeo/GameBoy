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
        dmgDisplayView = DmgDisplay(frame: NSRect(x: 0, y: 0, width: 160, height: 133))
        self.view = dmgDisplayView
    }
    
    func didUpdate(buffer: [UInt8]) {
        print("Got update")
        dmgDisplayView?.updateView(buffer: buffer)
        DispatchQueue.main.async {
            self.view.needsDisplay = true
        }
        
    }
    
}

class DmgDisplay : NSView {
    
    var pixelBuf: [UInt8]!
    
    // DMG pixel colors
    let pixelColors = [[255, 15, 56, 15], [255, 48, 98, 49], [255, 139, 172,15], [255, 155, 188, 15]]
    
    func updateView(buffer: [UInt8]) {
        pixelBuf = buffer
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard pixelBuf != nil else { return }
        
        let rep = NSBitmapImageRep(focusedViewRect: dirtyRect)
        
        guard let h = rep?.pixelsHigh, let w = rep?.pixelsWide else {
            return
        }
        
        for y in 0 ..< h {
            for x in 0 ..< w {
                let pixVal = pixelBuf[y*x]
                var pixel = pixelColors[Int(pixVal)]
                rep?.setPixel(UnsafeMutablePointer<Int>(&pixel) , atX: x, y: y)
            }
        }
        
        rep?.draw(in: dirtyRect)
    }
}
