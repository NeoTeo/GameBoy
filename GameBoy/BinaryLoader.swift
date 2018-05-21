//
//  BinaryLoader.swift
//  GameBoy
//
//  Created by Teo Sartori on 18/05/2018.
//  Copyright © 2018 Matteo Sartori. All rights reserved.
//

import Foundation

func loadBinary(from filename: URL) throws -> [UInt8] {
    
    do {
        let data = try Data(contentsOf: filename, options: .mappedIfSafe)
        
        return Array(data)
    } catch {
        throw error
    }
}
