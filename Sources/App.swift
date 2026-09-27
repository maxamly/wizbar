import SwiftUI

@main
struct WizBarApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            Panel().environmentObject(store)
        } label: {
            Image(systemName: store.bulbs.contains(where: \.on) ? "lightbulb.fill" : "lightbulb")
        }
        .menuBarExtraStyle(.window)

        Window("Set Up Lights", id: "setup") {
            SetupView().environmentObject(store)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}
