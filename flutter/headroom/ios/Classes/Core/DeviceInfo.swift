import Foundation

public enum Platform: String, Sendable, Hashable, Codable {
    case iOS
    case iOSSimulator = "iOS Simulator"
    case macOS
}

/// Hardware and OS facts that do not change during a probe.
public struct DeviceInfo: Sendable, Hashable, Codable {
    /// `iPhone14,5` on iOS, from uname; `MacBookPro17,1` on macOS, from `hw.model`,
    /// because uname there only says `arm64`.
    public let identifier: String
    /// `Apple M1` where the kernel exposes a brand string (macOS); nil on iOS.
    public let chip: String?
    public let platform: Platform
    public let osVersion: String
    public let osBuild: String
    public let logicalCPUs: Int

    /// Simulator figures are the host Mac's and must never pass for phone data.
    public var isSimulator: Bool { platform == .iOSSimulator }

    static func current() -> DeviceInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var osVersion = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 {
            osVersion += ".\(version.patchVersion)"
        }
        return DeviceInfo(
            identifier: identifier(),
            chip: Sysctl.string("machdep.cpu.brand_string"),
            platform: platform,
            osVersion: osVersion,
            osBuild: osBuild(),
            logicalCPUs: ProcessInfo.processInfo.activeProcessorCount
        )
    }

    private static var platform: Platform {
        #if targetEnvironment(simulator)
        .iOSSimulator
        #elseif os(macOS)
        .macOS
        #else
        .iOS
        #endif
    }

    private static func identifier() -> String {
        #if targetEnvironment(simulator)
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        #endif
        #if os(macOS)
        return Sysctl.string("hw.model") ?? Sysctl.unameMachine()
        #else
        return Sysctl.unameMachine()
        #endif
    }

    private static func osBuild() -> String {
        #if targetEnvironment(simulator)
        // kern.osversion in the simulator is the host's build, not the runtime's.
        if let runtime = ProcessInfo.processInfo.environment["SIMULATOR_RUNTIME_BUILD_VERSION"] {
            return runtime
        }
        #endif
        return Sysctl.string("kern.osversion") ?? "unknown"
    }
}
