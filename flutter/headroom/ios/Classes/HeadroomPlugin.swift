import Flutter
import os

/// The `headroom/probe` channel.
///
/// `probe` takes the Dart `ProbeOptions` as a dictionary, runs the Swift
/// core's probe and answers with the report as a JSON string; `cancel` stops
/// a running probe at its next kernel boundary, after which the pending
/// `probe` call fails with code `cancelled`. The probe itself runs off the
/// platform thread inside the core; this class only forwards.
public final class HeadroomPlugin: NSObject, FlutterPlugin, Sendable {
    /// Flutter requires a result to be delivered on the platform thread. The
    /// block is not Sendable as imported; it is only ever called from the main
    /// actor here.
    private struct Reply: @unchecked Sendable {
        let send: FlutterResult
    }

    private enum Outcome: Sendable {
        case report(String)
        case failure(code: String, message: String)
    }

    private struct State: Sendable {
        var generation = 0
        var active: Int?
        var task: Task<Void, Never>?
        var cancelRequested = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "headroom/probe", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(HeadroomPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "probe":
            probe(arguments: call.arguments, reply: Reply(send: result))
        case "cancel":
            state.withLock { state in
                state.cancelRequested = true
                state.task?.cancel()
            }
            result(nil)
        default:
            result(FlutterError(code: "notImplemented", message: "\(call.method) is not a headroom method", details: nil))
        }
    }

    private func probe(arguments: Any?, reply: Reply) {
        let options: ProbeOptions
        do {
            options = try Self.options(from: arguments)
        } catch {
            reply.send(FlutterError(code: "invalidOptions", message: "\(error)", details: nil))
            return
        }
        let busy = state.withLock { $0.active != nil }
        if busy {
            reply.send(FlutterError(code: "busy", message: "a probe is already running", details: nil))
            return
        }

        let generation: Int = state.withLock { state in
            state.generation += 1
            state.active = state.generation
            state.cancelRequested = false
            return state.generation
        }
        let task = Task { [state] in
            let outcome = await Self.run(options)
            state.withLock { state in
                if state.active == generation {
                    state.active = nil
                    state.task = nil
                }
            }
            await MainActor.run {
                switch outcome {
                case let .report(json):
                    reply.send(json)
                case let .failure(code, message):
                    reply.send(FlutterError(code: code, message: message, details: nil))
                }
            }
        }
        state.withLock { state in
            // The task may already have finished; only a still-active probe is
            // kept for `cancel`, and a cancel that raced the start is honoured.
            if state.active == generation {
                state.task = task
                if state.cancelRequested { task.cancel() }
            }
        }
    }

    private static func run(_ options: ProbeOptions) async -> Outcome {
        do {
            let report = try await Headroom.probe(options: options)
            return .report(String(decoding: try report.jsonData(), as: UTF8.self))
        } catch is CancellationError {
            return .failure(code: "cancelled", message: "the probe was cancelled")
        } catch let error as HeadroomError {
            if case .invalidOptions = error {
                return .failure(code: "invalidOptions", message: "\(error)")
            }
            return .failure(code: "probeFailed", message: "\(error)")
        } catch {
            return .failure(code: "probeFailed", message: "\(error)")
        }
    }

    private enum ArgumentError: Error, CustomStringConvertible {
        case notAnObject
        case wrongType(key: String, expected: String)

        var description: String {
            switch self {
            case .notAnObject: "probe options must be a map"
            case let .wrongType(key, expected): "probe option '\(key)' must be \(expected)"
            }
        }
    }

    /// The Dart `ProbeOptions.toChannelArguments()` map; absent keys keep the
    /// core's defaults, and the core validates the sizes.
    private static func options(from arguments: Any?) throws -> ProbeOptions {
        var options = ProbeOptions()
        guard let arguments else { return options }
        guard let map = arguments as? [String: Any] else { throw ArgumentError.notAnObject }

        func int(_ key: String) throws -> Int? {
            guard let value = map[key] else { return nil }
            guard let number = value as? Int else { throw ArgumentError.wrongType(key: key, expected: "an integer") }
            return number
        }
        func bool(_ key: String) throws -> Bool? {
            guard let value = map[key] else { return nil }
            guard let flag = value as? Bool else { throw ArgumentError.wrongType(key: key, expected: "a boolean") }
            return flag
        }

        if let value = try int("gpuArrayBytes") { options.gpuArrayBytes = value }
        if let value = try int("gpuWarmupIterations") { options.gpuWarmupIterations = value }
        if let value = try int("gpuTimedIterations") { options.gpuTimedIterations = value }
        if let value = try int("cpuArrayBytes") { options.cpuArrayBytes = value }
        if let value = try int("cpuThreads") { options.cpuThreads = value }
        if let value = try int("cpuWarmupIterations") { options.cpuWarmupIterations = value }
        if let value = try int("cpuTimedIterations") { options.cpuTimedIterations = value }
        if let value = try bool("runsGPUProbe") { options.runsGPUProbe = value }
        if let value = try bool("runsCPUProbe") { options.runsCPUProbe = value }
        return options
    }
}
