#include "headroom.h"

#if defined(__APPLE__)
#include <TargetConditionals.h>
#include <sys/sysctl.h>
#if TARGET_OS_IPHONE && !TARGET_OS_MACCATALYST
#include <os/proc.h>
#define HEADROOM_HAS_AVAILABLE_MEMORY 1
#endif
#endif

int headroom_performance_cpus(void) {
#if defined(__APPLE__)
    /* perflevel0 is the highest-performance cluster on Apple silicon. */
    int count = 0;
    size_t size = sizeof(count);
    if (sysctlbyname("hw.perflevel0.logicalcpu", &count, &size, NULL, 0) == 0 && count > 0) {
        return count;
    }
#endif
    return 0;
}

uint64_t headroom_available_memory_bytes(void) {
#if defined(HEADROOM_HAS_AVAILABLE_MEMORY)
    return (uint64_t)os_proc_available_memory();
#else
    return 0;
#endif
}

int headroom_c_optimized(void) {
#if defined(__OPTIMIZE__)
    return 1;
#else
    return 0;
#endif
}
