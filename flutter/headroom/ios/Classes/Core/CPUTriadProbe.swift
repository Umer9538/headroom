import CHeadroom

/// STREAM triad on the CPU, run by the C target so the figure stays
/// comparable with the Flutter plugin's later.
struct CPUTriadProbe: Sendable {
    var arrayBytes: Int
    /// 0 means automatic: see `candidateThreadCounts`.
    var threads: Int
    var warmupIterations: Int
    var timedIterations: Int

    /// Thread counts an automatic run tries, in order. Static slices make every
    /// iteration wait for the slowest core, and on an M1 the efficiency cores
    /// pull the eight-thread figure about 10% under the four-thread one, so
    /// both the performance cluster alone and every core are tried and the
    /// higher median is reported. The other attempt is kept for the record.
    static func candidateThreadCounts(requested: Int) -> [Int] {
        if requested > 0 { return [requested] }
        let all = Int(headroom_online_cpus())
        let performance = Int(headroom_performance_cpus())
        return performance > 0 && performance < all ? [performance, all] : [all]
    }

    func run(isCancelled: () -> Bool) throws -> CPUBandwidth {
        var attempts: [CPUBandwidth.Attempt] = []
        for count in Self.candidateThreadCounts(requested: threads) {
            if isCancelled() { throw CancellationError() }
            attempts.append(CPUBandwidth.Attempt(threads: count, triad: try triad(threads: count)))
        }
        let best = CPUBandwidth.best(of: attempts)
        return CPUBandwidth(
            threads: best.threads,
            arrayBytes: arrayBytes,
            compiledWithOptimisation: headroom_c_optimized() != 0,
            triad: best.triad,
            attempts: attempts
        )
    }

    private func triad(threads: Int) throws -> BandwidthFigure {
        let elements = arrayBytes / MemoryLayout<Float>.stride
        var seconds = [Double](repeating: 0, count: timedIterations)
        var verified: Int32 = 0
        let status = headroom_cpu_triad(
            elements, Int32(threads), Int32(warmupIterations), Int32(timedIterations),
            &seconds, &verified
        )
        guard status == HEADROOM_OK else {
            throw HeadroomError.cpuProbeFailed(code: status)
        }
        let correct = verified != 0
        return BandwidthFigure(
            kernel: .triad,
            bytesPerIteration: StreamKernel.triad.bytesPerIteration(arrayBytes: arrayBytes),
            iterationSeconds: seconds,
            verified: correct,
            basis: correct && headroom_c_optimized() != 0 ? .measured : .unknown
        )
    }
}
