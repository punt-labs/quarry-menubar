import SwiftUI

@main
struct QuarryMenuBarApp: App {
    var body: some Scene {
        MenuBarExtra("Quarry", systemImage: "doc.text.magnifyingglass") {
            Text("Quarry Search")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
