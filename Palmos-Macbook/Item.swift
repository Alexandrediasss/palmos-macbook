//
//  Item.swift
//  Palmos-Macbook
//
//  Created by Carlos Alexandre Dias Messias de Lima on 05/10/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
