import ServiceManagement
import SwiftUI

@main
struct WizBarApp: App {
    @StateObject private var store = Store()
    @StateObject private var updater = Updater()

    init() {
        // For scripted installs: `open -a WizBar --args --enable-launch-at-login`
        if CommandLine.arguments.contains("--enable-launch-at-login") {
            try? SMAppService.mainApp.register()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Panel().environmentObject(store).environmentObject(updater)
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
