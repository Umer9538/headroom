/// Probe sizing. The defaults take one to two seconds and stream arrays far
/// larger than any last-level cache in the devices Headroom has run on.
public struct ProbeOptions: Sendable, Hashable {
    /// Per array; three are allocated in private GPU memory.
    public var gpuArrayBytes = 128 << 20
    public var gpuWarmupIterations = 1
    public var gpuTimedIterations = 10

    /// Per array; three are allocated in system memory.
    public var cpuArrayBytes = 64 << 20
    /// 0 means one thread per online logical CPU.
    public var cpuThreads = 0
    public var cpuWarmupIterations = 1
    public var cpuTimedIterations = 7

    public var runsGPUProbe = true
    public var runsCPUProbe = true

    public init() {}

    func validate() throws {
        guard MetalBandwidthProbe.isValid(arrayBytes: gpuArrayBytes) else {
            throw HeadroomError.invalidOptions(
                "gpuArrayBytes must be a positive multiple of \(MetalBandwidthProbe.threadgroupWidth * MetalBandwidthProbe.vectorBytes)"
            )
        }
        guard cpuArrayBytes >= MemoryLayout<Float>.stride, cpuArrayBytes.isMultiple(of: MemoryLayout<Float>.stride) else {
            throw HeadroomError.invalidOptions("cpuArrayBytes must be a positive multiple of \(MemoryLayout<Float>.stride)")
        }
        guard gpuTimedIterations >= 1, cpuTimedIterations >= 1 else {
            throw HeadroomError.invalidOptions("each probe needs at least one timed iteration")
        }
        guard gpuWarmupIterations >= 0, cpuWarmupIterations >= 0, cpuThreads >= 0 else {
            throw HeadroomError.invalidOptions("warm-up iterations and thread count cannot be negative")
        }
    }
}
