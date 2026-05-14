import Foundation
import HyperXProtocol
import os

@MainActor
public final class MicController: ObservableObject {
    public enum Status: Equatable {
        case disconnected
        case connected
        case busy
        case error(String)
    }

    @Published public private(set) var status: Status = .disconnected

    private let logger = Logger(subsystem: "com.hyperx.rgb", category: "MicController")
    private let device: HIDDevice
    private var refreshLoop: RefreshLoop?
    private var currentUpper: RGB = .white
    private var currentLower: RGB = .white
    private var currentBrightness: Int = 100

    public init() {
        self.device = HIDDevice(
            vendorID: QC2SProtocol.vendorID,
            productID: QC2SProtocol.productID
        )
    }

    public func start() {
        device.onConnectionChange = { [weak self] connected in
            Task { @MainActor in
                guard let self else { return }
                self.status = connected ? .connected : .disconnected
                if connected {
                    self.startRefreshLoop()
                } else {
                    self.refreshLoop?.stop()
                    self.refreshLoop = nil
                }
            }
        }
        device.start()
    }

    public func stop() {
        refreshLoop?.stop()
        refreshLoop = nil
        device.stop()
    }

    public func setColor(upper: RGB, lower: RGB, brightness: Int) {
        currentUpper = upper
        currentLower = lower
        currentBrightness = max(0, min(100, brightness))
        refreshLoop?.updateColors(upper: upper, lower: lower, brightness: currentBrightness)
    }

    private func startRefreshLoop() {
        refreshLoop?.stop()
        let loop = RefreshLoop(device: device)
        loop.updateColors(upper: currentUpper, lower: currentLower, brightness: currentBrightness)
        loop.onError = { [weak self] error in
            Task { @MainActor in
                self?.status = .error(error.localizedDescription)
            }
        }
        loop.start()
        refreshLoop = loop
    }
}
