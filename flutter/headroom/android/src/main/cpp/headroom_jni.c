// JNI entry points for com.umer9538.headroom.NativeBridge: thin wrappers over
// the C core, which is never modified here.

#include <jni.h>

#include "headroom.h"

JNIEXPORT jint JNICALL Java_com_umer9538_headroom_NativeBridge_onlineCpus(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    return headroom_online_cpus();
}

JNIEXPORT jint JNICALL Java_com_umer9538_headroom_NativeBridge_performanceCpus(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    return headroom_performance_cpus();
}

JNIEXPORT jint JNICALL Java_com_umer9538_headroom_NativeBridge_cOptimized(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    return headroom_c_optimized();
}

/// headroom_cpu_triad with Java arrays: `seconds_out` receives one wall-clock
/// time per timed iteration and `verified_out[0]` becomes 1 when every element
/// held the expected value. Returns the core's HEADROOM_* status.
JNIEXPORT jint JNICALL Java_com_umer9538_headroom_NativeBridge_cpuTriad(
    JNIEnv *env, jclass clazz, jlong elements, jint threads, jint warmup, jint timed,
    jdoubleArray seconds_out, jintArray verified_out) {
    (void)clazz;
    if (elements <= 0 || timed < 1 || seconds_out == NULL || verified_out == NULL) {
        return HEADROOM_ERR_ARGS;
    }
    if ((*env)->GetArrayLength(env, seconds_out) < timed || (*env)->GetArrayLength(env, verified_out) < 1) {
        return HEADROOM_ERR_ARGS;
    }
    jdouble *seconds = (*env)->GetDoubleArrayElements(env, seconds_out, NULL);
    if (seconds == NULL) {
        return HEADROOM_ERR_ALLOC;
    }
    int verified = 0;
    int status = headroom_cpu_triad((size_t)elements, threads, warmup, timed, seconds, &verified);
    (*env)->ReleaseDoubleArrayElements(env, seconds_out, seconds, 0);
    jint verified_value = verified;
    (*env)->SetIntArrayRegion(env, verified_out, 0, 1, &verified_value);
    return status;
}
