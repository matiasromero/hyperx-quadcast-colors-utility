import SwiftUI
import AppKit
import HyperXCore
import HyperXProtocol

@main
struct HyperXRGBApp: App {
    @StateObject private var controller = MicController()
    @StateObject private var state = AppState()

    init() {
        NSApp?.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(controller)
                .environmentObject(state)
                .onAppear {
                    controller.start()
                    controller.setColor(
                        upper: state.upperColor,
                        lower: state.linkZones ? state.upperColor : state.lowerColor,
                        brightness: state.brightness
                    )
                }
        } label: {
            Image(systemName: "mic.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
