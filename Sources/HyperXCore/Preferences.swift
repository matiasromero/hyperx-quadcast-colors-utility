import Foundation
import HyperXProtocol

public struct Preferences {
    private enum Keys {
        static let upperRGB = "upperRGB"
        static let lowerRGB = "lowerRGB"
        static let brightness = "brightness"
        static let linkZones = "linkZones"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var upperColor: RGB {
        get { rgb(forKey: Keys.upperRGB) ?? RGB(red: 0xff, green: 0x00, blue: 0xff) }
        set { setRGB(newValue, forKey: Keys.upperRGB) }
    }

    public var lowerColor: RGB {
        get { rgb(forKey: Keys.lowerRGB) ?? RGB(red: 0x00, green: 0xff, blue: 0xff) }
        set { setRGB(newValue, forKey: Keys.lowerRGB) }
    }

    public var brightness: Int {
        get {
            let stored = defaults.integer(forKey: Keys.brightness)
            return stored == 0 ? 100 : stored
        }
        set { defaults.set(max(0, min(100, newValue)), forKey: Keys.brightness) }
    }

    public var linkZones: Bool {
        get { defaults.object(forKey: Keys.linkZones) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.linkZones) }
    }

    private func rgb(forKey key: String) -> RGB? {
        guard let dict = defaults.dictionary(forKey: key),
              let r = dict["r"] as? Int,
              let g = dict["g"] as? Int,
              let b = dict["b"] as? Int else { return nil }
        return RGB(red: UInt8(r & 0xff), green: UInt8(g & 0xff), blue: UInt8(b & 0xff))
    }

    private func setRGB(_ color: RGB, forKey key: String) {
        defaults.set(["r": Int(color.red), "g": Int(color.green), "b": Int(color.blue)], forKey: key)
    }
}
