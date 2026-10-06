//
//  Palmos_MacbookApp.swift
//  Palmos-Macbook
//
//  Created by Carlos Alexandre Dias Messias de Lima on 05/10/26.
//

import SwiftUI
import SwiftData

@main
struct Palmos_MacbookApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
