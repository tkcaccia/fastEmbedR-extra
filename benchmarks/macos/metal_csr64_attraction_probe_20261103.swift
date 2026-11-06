import Darwin
import Foundation
import Metal

guard CommandLine.arguments.count == 2,
      let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue() else {
    fatalError("Need a Stefano folder and a Metal device")
}
let folder = CommandLine.arguments[1]
let vertices = 4
let dimensions = 3
let base: UInt64 = UInt64(Int32.max) + 23
let offsets: [UInt64] = [base, base + 2, base + 4,
                         base + 6, base + 8]
let targets: [UInt32] = [1, 2, 0, 3, 0, 3, 1, 2]
let weights: [Float] = [0.1, 0.2, 0.3, 0.4,
                        0.5, 0.6, 0.7, 0.8]
let layout: [Float] = [0, 0, 0, 1, 0, 0,
                       0, 1, 0, 0, 0, 1]

func mappedBuffer<T>(_ name: String, _ values: [T]) throws
    -> (Int32, UnsafeMutableRawPointer, Int, any MTLBuffer, String) {
    let path = folder + "/" + name
    let bytes = values.count * MemoryLayout<T>.stride
    let fd = open(path, O_CREAT | O_EXCL | O_RDWR, 0o600)
    guard fd >= 0, ftruncate(fd, off_t(bytes)) == 0 else {
        throw NSError(domain: "file", code: 1)
    }
    let address = mmap(nil, bytes, PROT_READ | PROT_WRITE,
                       MAP_SHARED, fd, 0)
    guard address != MAP_FAILED, let mapped = address else {
        close(fd)
        unlink(path)
        throw NSError(domain: "mmap", code: 2)
    }
    _ = values.withUnsafeBytes { source in
        memcpy(mapped, source.baseAddress!, bytes)
    }
    guard let buffer = device.makeBuffer(bytesNoCopy: mapped,
        length: bytes, options: .storageModeShared,
        deallocator: nil) else {
        munmap(mapped, bytes)
        close(fd)
        unlink(path)
        throw NSError(domain: "Metal", code: 3)
    }
    return (fd, mapped, bytes, buffer, path)
}

let source = """
#include <metal_stdlib>
using namespace metal;
kernel void attract(device const ulong* offsets [[buffer(0)]],
                    device const uint* targets [[buffer(1)]],
                    device const float* weights [[buffer(2)]],
                    device const float* layout [[buffer(3)]],
                    device float* gradient [[buffer(4)]],
                    constant ulong& base [[buffer(5)]],
                    constant uint& dimensions [[buffer(6)]],
                    uint row [[thread_position_in_grid]]) {
  if (row >= 4u) return;
  float sum[3] = {0.0f, 0.0f, 0.0f};
  for (ulong edge = offsets[row] - base;
       edge < offsets[row + 1u] - base; ++edge) {
    uint target = targets[edge];
    float distance2 = 0.0f;
    for (uint axis = 0u; axis < dimensions; ++axis) {
      float diff = layout[row * dimensions + axis] -
                   layout[target * dimensions + axis];
      distance2 += diff * diff;
    }
    float factor = weights[edge] / (1.0f + distance2);
    for (uint axis = 0u; axis < dimensions; ++axis) {
      sum[axis] += factor *
        (layout[row * dimensions + axis] -
         layout[target * dimensions + axis]);
    }
  }
  for (uint axis = 0u; axis < dimensions; ++axis)
    gradient[row * dimensions + axis] = sum[axis];
}
"""

let files = try [mappedBuffer("csr64-offsets.u64", offsets),
                 mappedBuffer("csr64-targets.u32", targets),
                 mappedBuffer("csr64-weights.f32", weights)]
defer {
    for (fd, address, bytes, _, path) in files {
        munmap(address, bytes)
        close(fd)
        unlink(path)
    }
}
let library = try device.makeLibrary(source: source, options: nil)
let pipeline = try device.makeComputePipelineState(
    function: library.makeFunction(name: "attract")!)
let coordinates = layout.withUnsafeBytes { bytes in
    device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count,
                      options: .storageModeShared)!
}
let result = device.makeBuffer(length: layout.count * 4,
                               options: .storageModeShared)!
let command = queue.makeCommandBuffer()!
let encoder = command.makeComputeCommandEncoder()!
encoder.setComputePipelineState(pipeline)
for i in 0..<3 { encoder.setBuffer(files[i].3, offset: 0, index: i) }
encoder.setBuffer(coordinates, offset: 0, index: 3)
encoder.setBuffer(result, offset: 0, index: 4)
var offsetBase = base
var dims = UInt32(dimensions)
encoder.setBytes(&offsetBase, length: 8, index: 5)
encoder.setBytes(&dims, length: 4, index: 6)
encoder.dispatchThreads(MTLSize(width: vertices, height: 1, depth: 1),
    threadsPerThreadgroup: MTLSize(width: vertices, height: 1, depth: 1))
encoder.endEncoding()
command.commit()
command.waitUntilCompleted()
guard command.status == .completed else {
    fatalError("Metal attraction failed: \(String(describing: command.error))")
}
let actual = result.contents().bindMemory(to: Float.self,
                                          capacity: layout.count)
for row in 0..<vertices {
    var expected = [Float](repeating: 0, count: dimensions)
    let start = Int(offsets[row] - base)
    let end = Int(offsets[row + 1] - base)
    for edge in start..<end {
        let target = Int(targets[edge])
        var distance2: Float = 0
        for axis in 0..<dimensions {
            let delta = layout[row * dimensions + axis] -
                        layout[target * dimensions + axis]
            distance2 += delta * delta
        }
        let factor = weights[edge] / (1 + distance2)
        for axis in 0..<dimensions {
            expected[axis] += factor *
                (layout[row * dimensions + axis] -
                 layout[target * dimensions + axis])
        }
    }
    for axis in 0..<dimensions {
        let index = row * dimensions + axis
        guard abs(actual[index] - expected[axis]) < 1.0e-6 else {
            fatalError("GPU/CPU attraction mismatch at \(index)")
        }
    }
}
print("DEVICE \(device.name)")
print("CSR64_MAPPED_ATTRACTION_PASS rows=\(vertices) edges=\(targets.count) " +
      "dimensions=\(dimensions) logical_edge_base=\(base)")
