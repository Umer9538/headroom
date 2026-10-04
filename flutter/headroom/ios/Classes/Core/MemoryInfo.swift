import CHeadroom
import Darwin
import Foundation

/// Installed and remaining memory. "Remaining" decides whether a model fits,
/// and only iOS exposes a per-process budget for it; elsewhere the figure is a
/// fallback carrying basis `.unknown`.
public struct MemoryInfo: Sendable, Hashable, Codable {
    public let physicalBytes: UInt64
    /// On an iPhone, `os_proc_available_memory`: what the process may still
    /// allocate before jetsam. On macOS, free + inactive + speculative pages,
    /// which is not a budget, so `.unknown`. In the simulator the host's
    /// figure says nothing about a phone, so `.unknown` there too.
    public let availableBytes: Quantity<UInt64>

    static func current() -> MemoryInfo {
        let physical = ProcessInfo.processInfo.physicalMemory
        #if !targetEnvironment(simulator)
        let budget = headroom_available_memory_bytes()
        if budget > 0 {
            return MemoryInfo(physicalBytes: physical, availableBytes: Quantity(budget, basis: .measured))
        }
        #endif
        return MemoryInfo(
            physicalBytes: physical,
            availableBytes: Quantity(reclaimablePageBytes() ?? 0, basis: .unknown)
        )
    }

    /// Why an allocation of `bytes` should not be attempted, or nil when it may
    /// be. A probe never allocates past the budget the OS reports, because the
    /// OS enforces it by killing the process rather than failing the call.
    /// Where no budget is known, nothing is refused.
    func refusal(allocating bytes: Int) -> String? {
        guard availableBytes.basis == .measured, bytes > availableBytes.value else { return nil }
        return "it needs \(bytes / 1_000_000) MB of memory and the OS reports \(availableBytes.value / 1_000_000) MB available to this process"
    }

    private static func reclaimablePageBytes() -> UInt64? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.speculative_count)
        return pages * UInt64(sysconf(_SC_PAGESIZE))
    }
}
