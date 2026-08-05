import Observation
import UIKit

enum CaptureQualityTier: Int, Comparable, Sendable {
    case full = 0
    case reduced = 1
    case minimal = 2

    static func < (lhs: CaptureQualityTier, rhs: CaptureQualityTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var statusMessage: String? {
        switch self {
        case .full: nil
        case .reduced: "Quality reduced — device is warm"
        case .minimal: "Quality minimized — device is hot"
        }
    }
}

@MainActor @Observable
final class DeviceConditionManager {
    private nonisolated let logger = AppLogger.make(category: "DeviceCondition")

    private(set) var qualityTier: CaptureQualityTier = .full
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    private(set) var batteryLevel: Float = 1.0
    private(set) var isLowPowerModeEnabled = false

    private var thermalObserver: NSObjectProtocol?
    private var powerModeObserver: NSObjectProtocol?
    private var batteryTimer: Timer?

    func startMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBatteryLevel()
        updateThermalState()
        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateThermalState()
            }
        }

        powerModeObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
                self?.recalculateTier()
            }
        }

        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateBatteryLevel()
            }
        }
    }

    func stopMonitoring() {
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
        if let powerModeObserver { NotificationCenter.default.removeObserver(powerModeObserver) }
        batteryTimer?.invalidate()
        thermalObserver = nil
        powerModeObserver = nil
        batteryTimer = nil
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    // MARK: - Private

    private func updateThermalState() {
        thermalState = ProcessInfo.processInfo.thermalState
        logger.info("Thermal state: \(String(describing: self.thermalState.rawValue))")
        recalculateTier()
    }

    private func updateBatteryLevel() {
        batteryLevel = UIDevice.current.batteryLevel
        recalculateTier()
    }

    private func recalculateTier() {
        let newTier: CaptureQualityTier
        switch thermalState {
        case .critical, .serious:
            newTier = .minimal
        case .fair:
            newTier = .reduced
        case .nominal:
            if isLowPowerModeEnabled || batteryLevel < 0.1 {
                newTier = .reduced
            } else {
                newTier = .full
            }
        @unknown default:
            newTier = .full
        }

        if newTier != qualityTier {
            logger.info("Quality tier changed: \(self.qualityTier.rawValue) → \(newTier.rawValue)")
            qualityTier = newTier
        }
    }
}
