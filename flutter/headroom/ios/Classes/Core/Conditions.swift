import Foundation
#if canImport(UIKit)
import UIKit
#elseif os(macOS)
import IOKit.ps
#endif

public enum ThermalState: String, Sendable, Hashable, Codable {
    case nominal
    case fair
    case serious
    case critical
    /// A state this build does not know; newer OS releases may add one.
    case unrecognised

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .unrecognised
        }
    }
}

public enum PowerSource: String, Sendable, Hashable, Codable {
    case battery
    case external
    case unknown
}

/// What the device was doing when the probe ran: the context without which a
/// bandwidth figure cannot be compared with another.
public struct Conditions: Sendable, Hashable, Codable {
    public let thermalState: ThermalState
    public let isLowPowerModeEnabled: Bool
    public let powerSource: PowerSource
    /// 0...1 where the OS reports it (iPhone); nil elsewhere.
    public let batteryLevel: Double?

    static func current() async -> Conditions {
        let (powerSource, batteryLevel) = await power()
        return Conditions(
            thermalState: ThermalState(ProcessInfo.processInfo.thermalState),
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            powerSource: powerSource,
            batteryLevel: batteryLevel
        )
    }

    #if canImport(UIKit)
    private static func power() async -> (PowerSource, Double?) {
        // UIDevice is main-actor bound; this is a microsecond read, not the probe.
        await MainActor.run {
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            let source: PowerSource = switch device.batteryState {
            case .unplugged: .battery
            case .charging, .full: .external
            case .unknown: .unknown
            @unknown default: .unknown
            }
            let level = device.batteryLevel
            return (source, level >= 0 ? Double(level) : nil)
        }
    }
    #elseif os(macOS)
    private static func power() async -> (PowerSource, Double?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else {
            return (.unknown, nil)
        }
        switch providing as String {
        case kIOPSACPowerValue: return (.external, nil)
        case kIOPSBatteryPowerValue: return (.battery, nil)
        default: return (.unknown, nil)
        }
    }
    #else
    private static func power() async -> (PowerSource, Double?) {
        (.unknown, nil)
    }
    #endif
}
