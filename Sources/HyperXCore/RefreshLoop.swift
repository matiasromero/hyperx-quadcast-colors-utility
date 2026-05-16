import Foundation
import HyperXProtocol
import os

final class RefreshLoop {
    private let logger = Logger(subsystem: "com.hyperx.rgb", category: "RefreshLoop")
    private let device: HIDDevice
    private let queue = DispatchQueue(label: "com.hyperx.rgb.refresh", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var header: Data = QC2SProtocol.buildHeaderPacket()
    private var dataPackets: [Data] = []
    private let lock = NSLock()

    var onError: ((Error) -> Void)?

    init(device: HIDDevice) {
        self.device = device
    }

    func updateColors(upper: RGB, lower: RGB, brightness: Int) {
        let packets = QC2SProtocol.buildSolidPackets(upper: upper, lower: lower, brightness: brightness)
        lock.lock()
        dataPackets = packets
        lock.unlock()
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        lock.lock()
        let packetsToSend = dataPackets
        let headerToSend = header
        lock.unlock()

        guard !packetsToSend.isEmpty else { return }

        do {
            try sendAndDrain(headerToSend)
            for packet in packetsToSend {
                try sendAndDrain(packet)
            }
        } catch {
            logger.error("Refresh tick failed: \(error.localizedDescription, privacy: .public)")
            onError?(error)
        }
    }

    private func sendAndDrain(_ data: Data) throws {
        device.drainPendingResponses()
        try device.sendReport(data)
        _ = device.waitForResponse(timeout: 0.05)
    }
}
