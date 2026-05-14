import Foundation

public struct RGB: Equatable, Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let black = RGB(red: 0, green: 0, blue: 0)
    public static let white = RGB(red: 255, green: 255, blue: 255)

    public func applyingBrightness(_ percent: Int) -> RGB {
        let clamped = max(0, min(100, percent))
        func scale(_ v: UInt8) -> UInt8 {
            UInt8(Int(v) * clamped / 100)
        }
        return RGB(red: scale(red), green: scale(green), blue: scale(blue))
    }
}

public enum QC2SProtocol {
    public static let vendorID: Int = 0x03f0
    public static let productID: Int = 0x02b5

    static let packetSize = 64
    static let solidPacketCount = 6
    static let ledCount = 108

    static let displayCode: UInt8 = 0x44
    static let packetCountCode: UInt8 = 0x01
    static let rgbPacketCode: UInt8 = 0x02
    static let responseCode: UInt8 = 0xff

    public static func buildHeaderPacket() -> Data {
        var data = Data(count: packetSize)
        data[0] = displayCode
        data[1] = packetCountCode
        data[2] = UInt8(solidPacketCount)
        return data
    }

    public static func buildSolidPackets(
        upper: RGB,
        lower: RGB,
        brightness: Int = 100
    ) -> [Data] {
        let upperAdjusted = upper.applyingBrightness(brightness)
        let lowerAdjusted = lower.applyingBrightness(brightness)

        var buffer = [UInt8](repeating: 0, count: solidPacketCount * packetSize)

        for pcknum in 0..<solidPacketCount {
            let base = pcknum * packetSize
            buffer[base] = displayCode
            buffer[base + 1] = rgbPacketCode
            buffer[base + 2] = UInt8(pcknum)
        }

        fillWithColor(
            buffer: &buffer,
            startOffset: 0,
            color: upperAdjusted,
            ledOffset: 0,
            iterations: ledCount / 2
        )

        fillWithColor(
            buffer: &buffer,
            startOffset: 2 * packetSize,
            color: lowerAdjusted,
            ledOffset: 14,
            iterations: ledCount / 2
        )

        var packets: [Data] = []
        packets.reserveCapacity(solidPacketCount)
        for pcknum in 0..<solidPacketCount {
            let base = pcknum * packetSize
            packets.append(Data(buffer[base..<(base + packetSize)]))
        }
        return packets
    }

    private static func fillWithColor(
        buffer: inout [UInt8],
        startOffset: Int,
        color: RGB,
        ledOffset: Int,
        iterations: Int
    ) {
        var p = startOffset + 4 + 3 * ledOffset
        writeColor(color, into: &buffer, at: p)

        for _ in 0...iterations {
            if (p + 3 - startOffset) % packetSize == 0 {
                p += 7
            } else {
                p += 3
            }
            guard p + 3 <= buffer.count else { return }
            writeColor(color, into: &buffer, at: p)
        }
    }

    private static func writeColor(_ color: RGB, into buffer: inout [UInt8], at index: Int) {
        buffer[index] = color.red
        buffer[index + 1] = color.green
        buffer[index + 2] = color.blue
    }

    public static func isValidResponse(_ response: Data, forCommand command: Data) -> Bool {
        guard response.count >= 15, command.count >= 1 else { return false }
        return response[0] == responseCode && response[14] == command[0]
    }
}
