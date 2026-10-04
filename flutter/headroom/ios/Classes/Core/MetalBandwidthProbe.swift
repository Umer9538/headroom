import Foundation
import Metal

/// STREAM over three private Metal buffers, timed by the GPU's own timestamps
/// and checked by reading samples of each kernel's output back.
struct MetalBandwidthProbe: Sendable {
    var arrayBytes: Int
    var warmupIterations: Int
    var timedIterations: Int

    /// Arrays are sized in whole threadgroups so the dispatch needs no
    /// non-uniform threadgroup support.
    static let threadgroupWidth = 256
    static let vectorBytes = MemoryLayout<SIMD4<Float>>.stride

    static func isValid(arrayBytes: Int) -> Bool {
        arrayBytes > 0 && arrayBytes.isMultiple(of: threadgroupWidth * vectorBytes)
    }

    /// One kernel in STREAM order, with the value its output buffer must hold
    /// afterwards. Starting from a = 1, b = 2, c = 0 and q = 3 the sequence is
    /// exact in float32: copy c = 1, scale b = 3, add c = 4, triad a = 15.
    private struct Step {
        let kernel: StreamKernel
        let function: String
        let outputIndex: Int
        let expected: Float
    }

    private static let initialValues: [Float] = [1, 2, 0]
    private static let scalar: Float = 3
    private static let steps = [
        Step(kernel: .copy, function: "stream_copy", outputIndex: 2, expected: 1),
        Step(kernel: .scale, function: "stream_scale", outputIndex: 1, expected: 3),
        Step(kernel: .add, function: "stream_add", outputIndex: 2, expected: 4),
        Step(kernel: .triad, function: "stream_triad", outputIndex: 0, expected: 15),
    ]

    func run(isCancelled: () -> Bool) throws -> GPUBandwidth {
        precondition(Self.isValid(arrayBytes: arrayBytes), "ProbeOptions.validate() admits only whole-threadgroup sizes")
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw HeadroomError.metalUnavailable("no Metal device")
        }
        // Command buffers are autoreleased; draining the pool here returns the
        // 3 × 128 MB to the system before the CPU probe allocates its own.
        return try autoreleasepool {
            let session = try Session(device: device, arrayBytes: arrayBytes)

            var figures: [StreamKernel: BandwidthFigure] = [:]
            for step in Self.steps {
                var seconds: [Double] = []
                for iteration in 0..<(warmupIterations + timedIterations) {
                    if isCancelled() { throw CancellationError() }
                    let elapsed = try session.dispatch(step.function)
                    if iteration >= warmupIterations {
                        seconds.append(elapsed)
                    }
                }
                let verified = try session.outputMatches(step.expected, bufferIndex: step.outputIndex)
                figures[step.kernel] = BandwidthFigure(
                    kernel: step.kernel,
                    bytesPerIteration: step.kernel.bytesPerIteration(arrayBytes: arrayBytes),
                    iterationSeconds: seconds,
                    verified: verified,
                    basis: verified ? .measured : .unknown
                )
            }
            return GPUBandwidth(
                deviceName: device.name,
                arrayBytes: arrayBytes,
                copy: figures[.copy]!,
                scale: figures[.scale]!,
                add: figures[.add]!,
                triad: figures[.triad]!
            )
        }
    }

    /// The Metal objects for one run. Not Sendable, so it lives entirely inside
    /// the blocking call that created it.
    private final class Session {
        private static let verificationWindowVectors = 256

        private let queue: any MTLCommandQueue
        private let pipelines: [String: any MTLComputePipelineState]
        private let buffers: [any MTLBuffer]
        private let readback: any MTLBuffer
        private let arrayBytes: Int

        init(device: any MTLDevice, arrayBytes: Int) throws {
            self.arrayBytes = arrayBytes
            guard let queue = device.makeCommandQueue() else {
                throw HeadroomError.metalUnavailable("could not create a command queue")
            }
            self.queue = queue

            let library: any MTLLibrary
            do {
                library = try device.makeLibrary(source: StreamShaders.source, options: nil)
            } catch {
                throw HeadroomError.shaderCompilationFailed(String(describing: error))
            }
            var pipelines: [String: any MTLComputePipelineState] = [:]
            for name in ["stream_fill"] + MetalBandwidthProbe.steps.map(\.function) {
                guard let function = library.makeFunction(name: name) else {
                    throw HeadroomError.shaderCompilationFailed("missing kernel \(name)")
                }
                let pipeline = try device.makeComputePipelineState(function: function)
                guard pipeline.maxTotalThreadsPerThreadgroup >= MetalBandwidthProbe.threadgroupWidth else {
                    throw HeadroomError.metalUnavailable(
                        "\(name) allows \(pipeline.maxTotalThreadsPerThreadgroup) threads per threadgroup, fewer than the \(MetalBandwidthProbe.threadgroupWidth) dispatched"
                    )
                }
                pipelines[name] = pipeline
            }
            self.pipelines = pipelines

            let windowBytes = Self.verificationWindowVectors * MetalBandwidthProbe.vectorBytes
            guard arrayBytes <= device.maxBufferLength,
                  let a = device.makeBuffer(length: arrayBytes, options: .storageModePrivate),
                  let b = device.makeBuffer(length: arrayBytes, options: .storageModePrivate),
                  let c = device.makeBuffer(length: arrayBytes, options: .storageModePrivate),
                  let readback = device.makeBuffer(length: 3 * windowBytes, options: .storageModeShared)
            else {
                throw HeadroomError.allocationFailed(bytes: 3 * arrayBytes)
            }
            buffers = [a, b, c]
            self.readback = readback

            // Private storage cannot be written from the CPU, so a kernel sets the start values.
            for (buffer, value) in zip(buffers, MetalBandwidthProbe.initialValues) {
                try fill(buffer, with: value)
            }
        }

        private var vectorCount: Int { arrayBytes / MetalBandwidthProbe.vectorBytes }

        private func fill(_ buffer: any MTLBuffer, with value: Float) throws {
            _ = try run { encoder in
                encoder.setComputePipelineState(pipelines["stream_fill"]!)
                encoder.setBuffer(buffer, offset: 0, index: 0)
                var value = value
                encoder.setBytes(&value, length: MemoryLayout<Float>.size, index: 1)
            }
        }

        /// Dispatches one kernel over the whole array and returns its GPU time in seconds.
        func dispatch(_ function: String) throws -> Double {
            try run { encoder in
                encoder.setComputePipelineState(pipelines[function]!)
                for (index, buffer) in buffers.enumerated() {
                    encoder.setBuffer(buffer, offset: 0, index: index)
                }
                var q = MetalBandwidthProbe.scalar
                encoder.setBytes(&q, length: MemoryLayout<Float>.size, index: 3)
            }
        }

        /// One command buffer per dispatch, so the GPU timestamps bracket exactly
        /// one kernel. Zero or non-finite timestamps (no GPU timing on this
        /// device) are an error, never a figure.
        private func run(_ encode: (any MTLComputeCommandEncoder) -> Void) throws -> Double {
            try autoreleasepool {
                guard let commandBuffer = queue.makeCommandBuffer(),
                      let encoder = commandBuffer.makeComputeCommandEncoder()
                else {
                    throw HeadroomError.metalUnavailable("could not create a command buffer")
                }
                encode(encoder)
                let width = MetalBandwidthProbe.threadgroupWidth
                encoder.dispatchThreadgroups(
                    MTLSize(width: vectorCount / width, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
                )
                encoder.endEncoding()
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                guard commandBuffer.status == .completed else {
                    throw HeadroomError.gpuExecutionFailed(commandBuffer.error.map { String(describing: $0) } ?? "status \(commandBuffer.status.rawValue)")
                }
                let elapsed = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
                guard elapsed.isFinite, elapsed > 0 else { throw HeadroomError.gpuTimestampsUnavailable }
                return elapsed
            }
        }

        /// Blits three windows (start, middle, end) of a buffer into shared memory
        /// and checks every element against `expected`.
        func outputMatches(_ expected: Float, bufferIndex: Int) throws -> Bool {
            try autoreleasepool {
                let windowBytes = Self.verificationWindowVectors * MetalBandwidthProbe.vectorBytes
                let offsets = [0, arrayBytes / 2, arrayBytes - windowBytes]
                guard let commandBuffer = queue.makeCommandBuffer(),
                      let blit = commandBuffer.makeBlitCommandEncoder()
                else {
                    throw HeadroomError.metalUnavailable("could not create a blit encoder")
                }
                for (window, offset) in offsets.enumerated() {
                    blit.copy(
                        from: buffers[bufferIndex], sourceOffset: offset,
                        to: readback, destinationOffset: window * windowBytes,
                        size: windowBytes
                    )
                }
                blit.endEncoding()
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                guard commandBuffer.status == .completed else {
                    throw HeadroomError.gpuExecutionFailed("readback failed")
                }
                let count = offsets.count * windowBytes / MemoryLayout<Float>.stride
                let samples = UnsafeBufferPointer(
                    start: readback.contents().assumingMemoryBound(to: Float.self),
                    count: count
                )
                return samples.allSatisfy { $0 == expected }
            }
        }
    }
}
