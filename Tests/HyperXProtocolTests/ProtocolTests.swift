import Testing
import Foundation
@testable import HyperXProtocol

@Suite("QC2SProtocol")
struct ProtocolTests {
    @Test("Header packet has correct codes and is 64 bytes")
    func headerPacket() {
        let header = QC2SProtocol.buildHeaderPacket()
        #expect(header.count == 64)
        #expect(header[0] == 0x44)
        #expect(header[1] == 0x01)
        #expect(header[2] == 0x06)
        for i in 3..<64 {
            #expect(header[i] == 0, "byte \(i) should be zero")
        }
    }

    @Test("Solid mode returns 6 packets of 64 bytes")
    func solidPacketsShape() {
        let red = RGB(red: 0xff, green: 0x00, blue: 0x00)
        let packets = QC2SProtocol.buildSolidPackets(upper: red, lower: red)
        #expect(packets.count == 6)
        for (i, p) in packets.enumerated() {
            #expect(p.count == 64, "packet \(i) should be 64 bytes")
        }
    }

    @Test("Each data packet has DISPLAY_CODE, RGB_CODE, and sequence number")
    func packetHeaders() {
        let red = RGB(red: 0xff, green: 0x00, blue: 0x00)
        let packets = QC2SProtocol.buildSolidPackets(upper: red, lower: red)
        for (i, p) in packets.enumerated() {
            #expect(p[0] == 0x44, "packet \(i) byte 0")
            #expect(p[1] == 0x02, "packet \(i) byte 1")
            #expect(p[2] == UInt8(i), "packet \(i) byte 2 (sequence)")
        }
    }

    @Test("Upper zone color starts at packet 0 byte 4")
    func upperZoneStart() {
        let red = RGB(red: 0xff, green: 0x00, blue: 0x00)
        let black = RGB.black
        let packets = QC2SProtocol.buildSolidPackets(upper: red, lower: black)
        #expect(packets[0][4] == 0xff, "upper R at packet 0 byte 4")
        #expect(packets[0][5] == 0x00, "upper G at packet 0 byte 5")
        #expect(packets[0][6] == 0x00, "upper B at packet 0 byte 6")
    }

    @Test("Lower zone color starts at packet 2 byte 46")
    func lowerZoneStart() {
        let black = RGB.black
        let green = RGB(red: 0x00, green: 0xff, blue: 0x00)
        let packets = QC2SProtocol.buildSolidPackets(upper: black, lower: green)
        #expect(packets[2][46] == 0x00, "lower R at packet 2 byte 46")
        #expect(packets[2][47] == 0xff, "lower G at packet 2 byte 47")
        #expect(packets[2][48] == 0x00, "lower B at packet 2 byte 48")
    }

    @Test("Brightness 50 scales channels")
    func brightnessHalf() {
        let red = RGB(red: 0xff, green: 0x00, blue: 0x00)
        let scaled = red.applyingBrightness(50)
        #expect(scaled.red == 127)
        #expect(scaled.green == 0)
        #expect(scaled.blue == 0)
    }

    @Test("Brightness 0 produces black")
    func brightnessZero() {
        let scaled = RGB.white.applyingBrightness(0)
        #expect(scaled == RGB.black)
    }

    @Test("Brightness 100 is no-op")
    func brightnessFull() {
        let cyan = RGB(red: 0x00, green: 0xff, blue: 0xff)
        #expect(cyan.applyingBrightness(100) == cyan)
    }

    @Test("Upper color repeats at expected offsets within packet 0")
    func upperRepeats() {
        let blue = RGB(red: 0x12, green: 0x34, blue: 0x56)
        let packets = QC2SProtocol.buildSolidPackets(upper: blue, lower: RGB.black)
        #expect(packets[0][4] == 0x12)
        #expect(packets[0][7] == 0x12)
        #expect(packets[0][10] == 0x12)
    }

    @Test("Response validation accepts valid response")
    func validResponse() {
        var rsp = Data(count: 15)
        rsp[0] = 0xff
        rsp[14] = 0x44
        let cmd = Data([0x44, 0x01, 0x06])
        #expect(QC2SProtocol.isValidResponse(rsp, forCommand: cmd))
    }

    @Test("Response validation rejects wrong response code")
    func wrongResponseCode() {
        var rsp = Data(count: 15)
        rsp[0] = 0xfe
        rsp[14] = 0x44
        let cmd = Data([0x44])
        #expect(!QC2SProtocol.isValidResponse(rsp, forCommand: cmd))
    }

    @Test("Response validation rejects mismatched command echo")
    func wrongCommandEcho() {
        var rsp = Data(count: 15)
        rsp[0] = 0xff
        rsp[14] = 0x55
        let cmd = Data([0x44])
        #expect(!QC2SProtocol.isValidResponse(rsp, forCommand: cmd))
    }

    @Test("Short response is invalid")
    func shortResponse() {
        let rsp = Data([0xff])
        let cmd = Data([0x44])
        #expect(!QC2SProtocol.isValidResponse(rsp, forCommand: cmd))
    }
}
