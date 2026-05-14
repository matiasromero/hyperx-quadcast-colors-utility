import Foundation
import HyperXProtocol

var failures: [String] = []
var passed = 0

func check(_ label: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        passed += 1
    } else {
        failures.append(label)
        print("FAIL: \(label)")
    }
}

print("Validating HyperX QC2S protocol builder...\n")

let header = QC2SProtocol.buildHeaderPacket()
check("header is 64 bytes", header.count == 64)
check("header[0] == 0x44", header[0] == 0x44)
check("header[1] == 0x01", header[1] == 0x01)
check("header[2] == 0x06", header[2] == 0x06)
check("header trailing bytes are zero", (3..<64).allSatisfy { header[$0] == 0 })

let red = RGB(red: 0xff, green: 0x00, blue: 0x00)
let packets = QC2SProtocol.buildSolidPackets(upper: red, lower: red)
check("solid returns 6 packets", packets.count == 6)
check("each packet is 64 bytes", packets.allSatisfy { $0.count == 64 })

for (i, p) in packets.enumerated() {
    check("packet \(i) byte[0] == 0x44", p[0] == 0x44)
    check("packet \(i) byte[1] == 0x02", p[1] == 0x02)
    check("packet \(i) byte[2] == \(i)",   p[2] == UInt8(i))
}

let onlyUpper = QC2SProtocol.buildSolidPackets(upper: red, lower: RGB.black)
check("upper R at packet0[4]", onlyUpper[0][4] == 0xff)
check("upper G at packet0[5]", onlyUpper[0][5] == 0x00)
check("upper B at packet0[6]", onlyUpper[0][6] == 0x00)
check("upper repeats at packet0[7]", onlyUpper[0][7] == 0xff)
check("upper repeats at packet0[10]", onlyUpper[0][10] == 0xff)

let green = RGB(red: 0x00, green: 0xff, blue: 0x00)
let onlyLower = QC2SProtocol.buildSolidPackets(upper: RGB.black, lower: green)
check("lower R at packet2[46]", onlyLower[2][46] == 0x00)
check("lower G at packet2[47]", onlyLower[2][47] == 0xff)
check("lower B at packet2[48]", onlyLower[2][48] == 0x00)

check("brightness 50 of 0xff -> 127", red.applyingBrightness(50).red == 127)
check("brightness 0 of white -> black", RGB.white.applyingBrightness(0) == RGB.black)
check("brightness 100 is no-op",
      RGB(red: 0x12, green: 0x34, blue: 0x56).applyingBrightness(100) == RGB(red: 0x12, green: 0x34, blue: 0x56))

var rsp = Data(count: 15)
rsp[0] = 0xff
rsp[14] = 0x44
check("valid response accepted", QC2SProtocol.isValidResponse(rsp, forCommand: Data([0x44])))
rsp[0] = 0xfe
check("wrong response code rejected", !QC2SProtocol.isValidResponse(rsp, forCommand: Data([0x44])))
rsp[0] = 0xff
rsp[14] = 0x55
check("wrong command echo rejected", !QC2SProtocol.isValidResponse(rsp, forCommand: Data([0x44])))
check("short response rejected", !QC2SProtocol.isValidResponse(Data([0xff]), forCommand: Data([0x44])))

print("\n\(passed) passed, \(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
