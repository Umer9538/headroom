public enum HeadroomError: Error, Sendable, Hashable {
    case invalidOptions(String)
    case metalUnavailable(String)
    case shaderCompilationFailed(String)
    case allocationFailed(bytes: Int)
    case gpuExecutionFailed(String)
    /// The command buffer completed without GPU timestamps, so nothing was timed.
    case gpuTimestampsUnavailable
    case cpuProbeFailed(code: Int32)
}

extension HeadroomError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .invalidOptions(reason): "invalid probe options: \(reason)"
        case let .metalUnavailable(reason): "Metal unavailable: \(reason)"
        case let .shaderCompilationFailed(reason): "STREAM shaders failed to compile: \(reason)"
        case let .allocationFailed(bytes): "could not allocate \(bytes) bytes of GPU memory"
        case let .gpuExecutionFailed(reason): "GPU command failed: \(reason)"
        case .gpuTimestampsUnavailable: "GPU timestamps unavailable on this device"
        case let .cpuProbeFailed(code): "CPU triad failed with code \(code)"
        }
    }
}
