import Foundation
import IOKit
import IOKit.hid
import os

public enum HIDError: Error, LocalizedError {
    case deviceNotFound
    case openFailed(IOReturn)
    case setReportFailed(IOReturn)
    case busy

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "HyperX Quadcast 2 S Controller not found. Is it plugged in?"
        case .openFailed(let r):
            return "Failed to open HID device (IOReturn 0x\(String(r, radix: 16)))."
        case .setReportFailed(let r):
            return "Failed to send USB packet (IOReturn 0x\(String(r, radix: 16)))."
        case .busy:
            return "Microphone is being used by another process."
        }
    }
}

public final class HIDDevice {
    private let logger = Logger(subsystem: "com.hyperx.rgb", category: "HIDDevice")
    private let vendorID: Int
    private let productID: Int

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?

    public private(set) var isConnected: Bool = false

    public var onConnectionChange: ((Bool) -> Void)?
    public var onInputReport: ((Data) -> Void)?
    public var onDeviceOpened: ((IOHIDDevice) -> Void)?

    private var inputBuffer = [UInt8](repeating: 0, count: 64)
    private let responseQueue = DispatchQueue(label: "com.hyperx.rgb.response")
    private var pendingResponses: [Data] = []
    private let responseSemaphore = DispatchSemaphore(value: 0)

    public init(vendorID: Int, productID: Int) {
        self.vendorID = vendorID
        self.productID = productID
    }

    public func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: vendorID,
            kIOHIDProductIDKey: productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            let me = Unmanaged<HIDDevice>.fromOpaque(ctx).takeUnretainedValue()
            me.handleDeviceConnected(device)
        }, opaqueSelf)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            let me = Unmanaged<HIDDevice>.fromOpaque(ctx).takeUnretainedValue()
            me.handleDeviceRemoved(device)
        }, opaqueSelf)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            logger.error("IOHIDManagerOpen failed: \(String(format: "0x%x", openResult))")
        }
        self.manager = manager
    }

    public func stop() {
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            self.device = nil
        }
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
        }
        isConnected = false
        onConnectionChange?(false)
    }

    private func handleDeviceConnected(_ device: IOHIDDevice) {
        let outputSize = (IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int) ?? 0
        let inputSize = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 0
        let usagePage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
        logger.info("Candidate HID interface: outSize=\(outputSize) inSize=\(inputSize) usagePage=0x\(String(usagePage, radix: 16))")
        guard outputSize >= 64 && inputSize >= 64 else {
            logger.info("Skipping (need both input and output >= 64 bytes)")
            return
        }
        if self.device != nil {
            logger.info("Additional matching interface ignored")
            return
        }
        let open = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard open == kIOReturnSuccess else {
            logger.error("IOHIDDeviceOpen failed: \(String(format: "0x%x", open))")
            return
        }
        logger.info("Device opened (seized)")

        inputBuffer.withUnsafeMutableBufferPointer { buf in
            let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(
                device,
                buf.baseAddress!,
                CFIndex(buf.count),
                { ctx, _, _, _, _, report, reportLength in
                    guard let ctx else { return }
                    let me = Unmanaged<HIDDevice>.fromOpaque(ctx).takeUnretainedValue()
                    let data = Data(bytes: report, count: reportLength)
                    me.handleInputReport(data)
                },
                opaqueSelf
            )
        }

        self.device = device
        isConnected = true
        onDeviceOpened?(device)
        onConnectionChange?(true)
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        logger.info("Device removed")
        if self.device == device {
            self.device = nil
        }
        isConnected = false
        onConnectionChange?(false)
    }

    private func handleInputReport(_ data: Data) {
        responseQueue.async { [weak self] in
            guard let self else { return }
            self.pendingResponses.append(data)
            self.responseSemaphore.signal()
        }
        onInputReport?(data)
    }

    public func waitForResponse(timeout: TimeInterval) -> Data? {
        let result = responseSemaphore.wait(timeout: .now() + timeout)
        guard result == .success else { return nil }
        return responseQueue.sync {
            guard !pendingResponses.isEmpty else { return nil }
            return pendingResponses.removeFirst()
        }
    }

    public func drainPendingResponses() {
        responseQueue.sync {
            pendingResponses.removeAll()
        }
        while responseSemaphore.wait(timeout: .now()) == .success {}
    }

    public func sendReport(_ data: Data) throws {
        guard let device else { throw HIDError.deviceNotFound }
        let reportID: CFIndex = 0
        let result = data.withUnsafeBytes { buf -> IOReturn in
            guard let base = buf.bindMemory(to: UInt8.self).baseAddress else {
                return IOReturn(kIOReturnNoMemory)
            }
            return IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                reportID,
                base,
                data.count
            )
        }
        if result != kIOReturnSuccess {
            logger.error("IOHIDDeviceSetReport failed: \(String(format: "0x%x", result))")
            if result == kIOReturnBusy || result == kIOReturnExclusiveAccess {
                throw HIDError.busy
            }
            throw HIDError.setReportFailed(result)
        }
    }
}
