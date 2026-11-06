#include <metal_stdlib>
using namespace metal;

kernel void atomic64_probe(
    device atomic_ulong* values [[buffer(0)]],
    uint row [[thread_position_in_grid]]) {
  if (row == 0u) {
    atomic_fetch_add_explicit(&values[0], ulong(1),
                              memory_order_relaxed);
  }
}
