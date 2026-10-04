package com.umer9538.headroom

/** The C core, through headroom_jni.c. */
internal object NativeBridge {
    const val OK = 0

    init {
        System.loadLibrary("headroom")
    }

    /** Logical CPUs online: headroom_online_cpus(). */
    @JvmStatic
    external fun onlineCpus(): Int

    /**
     * Logical CPUs in the highest-performance cluster, or 0 where the kernel
     * does not say: headroom_performance_cpus(). Android exposes no such
     * count, so this is 0 here today and the probe runs one all-core attempt.
     */
    @JvmStatic
    external fun performanceCpus(): Int

    /** Nonzero when the C core was compiled with optimisation. */
    @JvmStatic
    external fun cOptimized(): Int

    /**
     * STREAM triad over three float32 arrays of [elements] each, on [threads]
     * threads (0 = one per online CPU): [warmup] untimed iterations, then
     * [timed] timed ones whose wall-clock seconds land in [secondsOut].
     * [verifiedOut] (one element) becomes 1 when every result was correct.
     * Returns HEADROOM_OK (0) or an error code.
     */
    @JvmStatic
    external fun cpuTriad(
        elements: Long,
        threads: Int,
        warmup: Int,
        timed: Int,
        secondsOut: DoubleArray,
        verifiedOut: IntArray,
    ): Int
}
