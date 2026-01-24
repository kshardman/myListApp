//
//  myListsApp 2.swift
//  myLists
//
//  Created by Keith Sharman on 1/22/26.
//


import SwiftUI
import SwiftData

@main
struct myListsApp: App {
    let container: ModelContainer
    @StateObject private var undoCenter = UndoCenter()

    init() {
        do {
            let schema = Schema([ListDocument.self, ListItem.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            self.container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(undoCenter)
        }
        .modelContainer(container)
    }
}