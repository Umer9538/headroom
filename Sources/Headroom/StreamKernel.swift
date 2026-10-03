/// The four STREAM kernels, with the byte accounting the benchmark defines:
/// each array an element is read from or written to counts once.
public enum StreamKernel: String, Sendable, Hashable, Codable, CaseIterable {
    /// `c = a`
    case copy
    /// `b = q * c`
    case scale
    /// `c = a + b`
    case add
    /// `a = b + q * c`
    case triad

    /// Arrays streamed per element: one read and one write for copy and scale,
    /// two reads and one write for add and triad.
    public var arraysTouched: Int {
        switch self {
        case .copy, .scale: 2
        case .add, .triad: 3
        }
    }

    public func bytesPerIteration(arrayBytes: Int) -> Int {
        arraysTouched * arrayBytes
    }
}
