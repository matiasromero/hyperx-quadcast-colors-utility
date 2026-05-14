import Foundation
import HyperXCore
import HyperXProtocol

// Standalone CLI probe: connects to the mic, sends one full solid-color cycle,
// keeps the loop alive for ~3 seconds, then exits. Useful to validate that
// IOKit HID Manager can talk to the device without bringing up the SwiftUI app.

let args = CommandLine.arguments
let hex: String

if args.count >= 2 {
    hex = args[1]
} else {
    hex = "ff0000"
}

func parseHex(_ s: String) -> RGB? {
    var hex = s
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard hex.count == 6,
          let val = UInt32(hex, radix: 16) else { return nil }
    return RGB(
        red: UInt8((val >> 16) & 0xff),
        green: UInt8((val >> 8) & 0xff),
        blue: UInt8(val & 0xff)
    )
}

guard let color = parseHex(hex) else {
    print("usage: HIDProbe <rrggbb>")
    exit(2)
}

print("HyperXRGB HID probe — color #\(hex) for 3s")
print("Looking for VID 0x\(String(QC2SProtocol.vendorID, radix: 16)) PID 0x\(String(QC2SProtocol.productID, radix: 16))...")

let device = HIDDevice(
    vendorID: QC2SProtocol.vendorID,
    productID: QC2SProtocol.productID
)

let connectedSem = DispatchSemaphore(value: 0)

device.onConnectionChange = { connected in
    print("Connection change: \(connected ? "CONNECTED" : "disconnected")")
    if connected {
        connectedSem.signal()
    }
}
device.onInputReport = { data in
    let prefix = data.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
    print("Input report (\(data.count) bytes): \(prefix)...")
}

device.start()

device.onDeviceOpened = { hidDevice in
    let outSize = (IOHIDDeviceGetProperty(hidDevice, kIOHIDMaxOutputReportSizeKey as CFString) as? Int) ?? -1
    let inSize = (IOHIDDeviceGetProperty(hidDevice, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? -1
    let usagePage = (IOHIDDeviceGetProperty(hidDevice, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? -1
    print("Opened device: outputSize=\(outSize) inputSize=\(inSize) usagePage=0x\(String(usagePage, radix: 16))")
}

DispatchQueue.global().async {
    if connectedSem.wait(timeout: .now() + 3) == .timedOut {
        print("ERROR: device not found within 3s.")
        exit(1)
    }
    Thread.sleep(forTimeInterval: 0.3)

    func sendAndWait(_ data: Data, label: String) throws {
        device.drainPendingResponses()
        try device.sendReport(data)
        if let rsp = device.waitForResponse(timeout: 0.5) {
            let prefix = rsp.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
            print("  \(label) -> rsp[0]=0x\(String(format: "%02x", rsp[0])) rsp[14]=0x\(String(format: "%02x", rsp.count > 14 ? rsp[14] : 0)) (\(prefix))")
        } else {
            print("  \(label) -> NO RESPONSE within 500ms (continuing anyway)")
        }
    }

    do {
        let header = QC2SProtocol.buildHeaderPacket()
        let packets = QC2SProtocol.buildSolidPackets(upper: color, lower: color)
        // Loop for ~5 seconds so the user has time to look at the mic.
        let endTime = Date().addingTimeInterval(5.0)
        var cycle = 0
        while Date() < endTime {
            print("Cycle \(cycle)")
            try sendAndWait(header, label: "header")
            for (i, p) in packets.enumerated() {
                try sendAndWait(p, label: "packet \(i)")
            }
            cycle += 1
            Thread.sleep(forTimeInterval: 0.1)
        }
        print("Done. Exiting.")
        exit(0)
    } catch {
        print("ERROR: \(error)")
        exit(1)
    }
}

RunLoop.main.run()
