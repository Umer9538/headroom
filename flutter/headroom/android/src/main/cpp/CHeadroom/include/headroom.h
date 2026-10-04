#ifndef HEADROOM_H
#define HEADROOM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define HEADROOM_OK 0
#define HEADROOM_ERR_ARGS 1
#define HEADROOM_ERR_ALLOC 2
#define HEADROOM_ERR_THREAD 3

/// STREAM triad `a[i] = b[i] + q * c[i]` over three float32 arrays of `elements`
/// each, split across `threads` POSIX threads (0 = one per online logical CPU).
///
/// Runs `warmup` untimed iterations, then `timed` timed ones, and writes the
/// wall-clock seconds of each timed iteration to `seconds_out[0 ..< timed]`.
/// Statistics are left to the caller. `verified_out` becomes 1 when every element
/// of `a` holds the expected value afterwards, 0 otherwise.
///
/// Returns HEADROOM_OK or one of the HEADROOM_ERR_* codes.
int headroom_cpu_triad(size_t elements, int threads, int warmup, int timed,
                       double *seconds_out, int *verified_out);

/// Bytes this process may still allocate before the OS reclaims it, from
/// os_proc_available_memory. Returns 0 where no such API exists (macOS).
uint64_t headroom_available_memory_bytes(void);

/// Nonzero when this target was compiled with optimisation. The triad loop uses
/// NEON intrinsics either way, but an unoptimised build spills every vector to
/// the stack and its figure is not a bandwidth ceiling.
int headroom_c_optimized(void);

/// Logical CPUs online, the thread count used when `threads` is 0.
int headroom_online_cpus(void);

/// Logical CPUs in the highest-performance cluster (`hw.perflevel0.logicalcpu`),
/// or 0 where the kernel does not say.
int headroom_performance_cpus(void);

#ifdef __cplusplus
}
#endif

#endif
