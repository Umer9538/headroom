/// A value and the basis on which it is reported.
public struct Quantity<Value: Sendable & Hashable & Codable>: Sendable, Hashable, Codable {
    public let value: Value
    public let basis: Basis

    public init(_ value: Value, basis: Basis) {
        self.value = value
        self.basis = basis
    }
}
