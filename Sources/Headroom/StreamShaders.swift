/// The STREAM kernels as Metal source, compiled at run time so the package
/// ships no metallib and needs no resource lookup to find one.
///
/// Buffer bindings are fixed across kernels: 0 = a, 1 = b, 2 = c, 3 = q.
/// Work is in float4, so each thread moves 16 bytes per array it touches.
enum StreamShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void stream_fill(device float4 *x [[buffer(0)]],
                            constant float &value [[buffer(1)]],
                            uint i [[thread_position_in_grid]]) {
        x[i] = float4(value);
    }

    kernel void stream_copy(device const float4 *a [[buffer(0)]],
                            device float4 *c [[buffer(2)]],
                            uint i [[thread_position_in_grid]]) {
        c[i] = a[i];
    }

    kernel void stream_scale(device float4 *b [[buffer(1)]],
                             device const float4 *c [[buffer(2)]],
                             constant float &q [[buffer(3)]],
                             uint i [[thread_position_in_grid]]) {
        b[i] = q * c[i];
    }

    kernel void stream_add(device const float4 *a [[buffer(0)]],
                           device const float4 *b [[buffer(1)]],
                           device float4 *c [[buffer(2)]],
                           uint i [[thread_position_in_grid]]) {
        c[i] = a[i] + b[i];
    }

    kernel void stream_triad(device float4 *a [[buffer(0)]],
                             device const float4 *b [[buffer(1)]],
                             device const float4 *c [[buffer(2)]],
                             constant float &q [[buffer(3)]],
                             uint i [[thread_position_in_grid]]) {
        a[i] = b[i] + q * c[i];
    }
    """
}
