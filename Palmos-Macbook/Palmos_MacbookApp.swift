//
//  Palmos_MacbookApp.swift
//  Palmos-Macbook
//
//  Created by Carlos Alexandre Dias Messias de Lima on 05/10/26.
//

import SwiftUI

@main
struct Palmos_MacbookApp: App {

    init() {
        MacNetworkManager.shared.startBrowsing()
    }

    var body: some Scene {
        MenuBarExtra("Palmos", systemImage: "waveform.badge.magnifyingglass") {
            MenuRootView()
        }
        // `.window` é necessário para hospedar controles como Slider no menu.
        .menuBarExtraStyle(.window)
    }
}
