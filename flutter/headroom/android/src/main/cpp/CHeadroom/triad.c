#include "headroom.h"

#include <pthread.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <pthread/qos.h>
#endif
#if defined(__ARM_NEON)
#include <arm_neon.h>
#endif

/* STREAM never writes b or c, so every iteration rewrites a with the same value
 * and the result can be checked exactly: 2 + 3 * 0.5 is representable in float32,
 * fused or not. */
#define TRIAD_Q 3.0f
#define TRIAD_B 2.0f
#define TRIAD_C 0.5f
#define TRIAD_EXPECTED 3.5f

/* Slices start on a 64-float (256-byte) boundary so no two threads share a cache line. */
#define SLICE_ALIGN 64

/* Neither macOS nor iOS ships pthread_barrier_t, so this is the textbook
 * generation-counting barrier. `released` lets a failed start unblock every
 * thread without a second, racier code path. */
typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    int total;
    int waiting;
    unsigned generation;
    int released;
} barrier_t;

static int barrier_init(barrier_t *b, int total) {
    if (pthread_mutex_init(&b->mutex, NULL) != 0) {
        return -1;
    }
    if (pthread_cond_init(&b->cond, NULL) != 0) {
        pthread_mutex_destroy(&b->mutex);
        return -1;
    }
    b->total = total;
    b->waiting = 0;
    b->generation = 0;
    b->released = 0;
    return 0;
}

static void barrier_destroy(barrier_t *b) {
    pthread_cond_destroy(&b->cond);
    pthread_mutex_destroy(&b->mutex);
}

static void barrier_wait(barrier_t *b) {
    pthread_mutex_lock(&b->mutex);
    unsigned arrived_in = b->generation;
    if (b->released) {
        pthread_mutex_unlock(&b->mutex);
        return;
    }
    if (++b->waiting == b->total) {
        b->waiting = 0;
        b->generation++;
        pthread_cond_broadcast(&b->cond);
    } else {
        while (b->generation == arrived_in && !b->released) {
            pthread_cond_wait(&b->cond, &b->mutex);
        }
    }
    pthread_mutex_unlock(&b->mutex);
}

static void barrier_release(barrier_t *b) {
    pthread_mutex_lock(&b->mutex);
    b->released = 1;
    pthread_cond_broadcast(&b->cond);
    pthread_mutex_unlock(&b->mutex);
}

typedef struct {
    float *a;
    float *b;
    float *c;
    size_t count;
    int iterations;
    barrier_t *start;
    barrier_t *done;
    double *seconds; /* per-iteration wall time, recorded by the calling thread only */
    int verified;
} slice_t;

static double now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

/* The vector loop is written out rather than left to the auto-vectoriser: at
 * -Os, Xcode's default for release C code, clang's cost model declines to
 * vectorise this loop and a scalar triad measures a single M1 core at 28 GB/s
 * instead of 52. Intrinsics make the figure independent of that decision. */
static void triad(float *restrict a, const float *restrict b, const float *restrict c, size_t n) {
    size_t i = 0;
#if defined(__ARM_NEON)
    const float32x4_t q = vdupq_n_f32(TRIAD_Q);
    for (; i + 16 <= n; i += 16) {
        vst1q_f32(a + i, vfmaq_f32(vld1q_f32(b + i), q, vld1q_f32(c + i)));
        vst1q_f32(a + i + 4, vfmaq_f32(vld1q_f32(b + i + 4), q, vld1q_f32(c + i + 4)));
        vst1q_f32(a + i + 8, vfmaq_f32(vld1q_f32(b + i + 8), q, vld1q_f32(c + i + 8)));
        vst1q_f32(a + i + 12, vfmaq_f32(vld1q_f32(b + i + 12), q, vld1q_f32(c + i + 12)));
    }
#endif
    for (; i < n; i++) {
        a[i] = b[i] + TRIAD_Q * c[i];
    }
}

static void slice_run(slice_t *s) {
    /* First touch happens on the thread that will stream the pages, outside the timed region. */
    for (size_t i = 0; i < s->count; i++) {
        s->a[i] = 0.0f;
        s->b[i] = TRIAD_B;
        s->c[i] = TRIAD_C;
    }
    for (int it = 0; it < s->iterations; it++) {
        /* The clock starts before the barrier so thread wake-up latency counts
         * against the figure: this is achieved bandwidth, not kernel time. */
        double t0 = s->seconds ? now_seconds() : 0.0;
        barrier_wait(s->start);
        triad(s->a, s->b, s->c, s->count);
        barrier_wait(s->done);
        if (s->seconds) {
            s->seconds[it] = now_seconds() - t0;
        }
    }
    int ok = 1;
    for (size_t i = 0; i < s->count; i++) {
        ok &= (s->a[i] == TRIAD_EXPECTED);
    }
    s->verified = ok;
}

static void *slice_thread(void *arg) {
    slice_run((slice_t *)arg);
    return NULL;
}

int headroom_online_cpus(void) {
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    return n > 0 ? (int)n : 1;
}

static int allocate(float **out, size_t bytes) {
    void *p = NULL;
    if (posix_memalign(&p, SLICE_ALIGN * sizeof(float), bytes) != 0) {
        return -1;
    }
    *out = (float *)p;
    return 0;
}

int headroom_cpu_triad(size_t elements, int threads, int warmup, int timed,
                       double *seconds_out, int *verified_out) {
    if (elements == 0 || warmup < 0 || timed < 1 || seconds_out == NULL || verified_out == NULL) {
        return HEADROOM_ERR_ARGS;
    }
    *verified_out = 0;
    if (threads <= 0) {
        threads = headroom_online_cpus();
    }
    size_t per_thread = elements / (size_t)threads;
    per_thread -= per_thread % SLICE_ALIGN;
    if (per_thread == 0) {
        threads = 1;
        per_thread = elements;
    }

    int status = HEADROOM_ERR_ALLOC;
    float *a = NULL, *b = NULL, *c = NULL;
    slice_t *slices = NULL;
    pthread_t *tids = NULL;
    double *all_seconds = NULL;
    int total = warmup + timed;
    size_t bytes = elements * sizeof(float);

    if (allocate(&a, bytes) != 0 || allocate(&b, bytes) != 0 || allocate(&c, bytes) != 0) {
        goto cleanup;
    }
    slices = calloc((size_t)threads, sizeof(slice_t));
    tids = calloc((size_t)threads, sizeof(pthread_t));
    all_seconds = calloc((size_t)total, sizeof(double));
    if (slices == NULL || tids == NULL || all_seconds == NULL) {
        goto cleanup;
    }

    barrier_t start, done;
    if (barrier_init(&start, threads) != 0) {
        status = HEADROOM_ERR_THREAD;
        goto cleanup;
    }
    if (barrier_init(&done, threads) != 0) {
        barrier_destroy(&start);
        status = HEADROOM_ERR_THREAD;
        goto cleanup;
    }

    size_t offset = 0;
    for (int t = 0; t < threads; t++) {
        size_t count = (t == threads - 1) ? elements - offset : per_thread;
        slices[t].a = a + offset;
        slices[t].b = b + offset;
        slices[t].c = c + offset;
        slices[t].count = count;
        slices[t].iterations = total;
        slices[t].start = &start;
        slices[t].done = &done;
        slices[t].seconds = (t == 0) ? all_seconds : NULL;
        offset += count;
    }

    pthread_attr_t attr;
    pthread_attr_init(&attr);
#if defined(__APPLE__)
    /* Lets the scheduler place workers on performance cores alongside the caller. */
    pthread_attr_set_qos_class_np(&attr, QOS_CLASS_USER_INITIATED, 0);
#endif
    int spawned = 1; /* the calling thread is slice 0 */
    for (int t = 1; t < threads; t++) {
        if (pthread_create(&tids[t], &attr, slice_thread, &slices[t]) != 0) {
            break;
        }
        spawned++;
    }
    pthread_attr_destroy(&attr);

    if (spawned == threads) {
        slice_run(&slices[0]);
        status = HEADROOM_OK;
    } else {
        barrier_release(&start);
        barrier_release(&done);
        status = HEADROOM_ERR_THREAD;
    }
    for (int t = 1; t < spawned; t++) {
        pthread_join(tids[t], NULL);
    }
    barrier_destroy(&start);
    barrier_destroy(&done);

    if (status == HEADROOM_OK) {
        int verified = 1;
        for (int t = 0; t < threads; t++) {
            verified &= slices[t].verified;
        }
        *verified_out = verified;
        for (int i = 0; i < timed; i++) {
            seconds_out[i] = all_seconds[warmup + i];
        }
    }

cleanup:
    free(all_seconds);
    free(tids);
    free(slices);
    free(c);
    free(b);
    free(a);
    return status;
}
