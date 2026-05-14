import Foundation
import SwiftUI
import HyperXCore
import HyperXProtocol

@MainActor
final class AppState: ObservableObject {
    private var prefs: Preferences

    @Published var upperColor: RGB
    @Published var lowerColor: RGB
    @Published var brightness: Int
    @Published var linkZones: Bool

    init(preferences: Preferences = Preferences()) {
        self.prefs = preferences
        self.upperColor = preferences.upperColor
        self.lowerColor = preferences.lowerColor
        self.brightness = preferences.brightness
        self.linkZones = preferences.linkZones
    }

    func persist() {
        prefs.upperColor = upperColor
        prefs.lowerColor = lowerColor
        prefs.brightness = brightness
        prefs.linkZones = linkZones
    }
}

extension RGB {
    var asColor: Color {
        Color(.sRGB,
              red: Double(red) / 255.0,
              green: Double(green) / 255.0,
              blue: Double(blue) / 255.0,
              opacity: 1.0)
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
        self = RGB(
            red: UInt8((ns.redComponent * 255).rounded().clamped(0, 255)),
            green: UInt8((ns.greenComponent * 255).rounded().clamped(0, 255)),
            blue: UInt8((ns.blueComponent * 255).rounded().clamped(0, 255))
        )
    }
}

private extension CGFloat {
    func clamped(_ minVal: CGFloat, _ maxVal: CGFloat) -> CGFloat {
        Swift.max(minVal, Swift.min(maxVal, self))
    }
}
