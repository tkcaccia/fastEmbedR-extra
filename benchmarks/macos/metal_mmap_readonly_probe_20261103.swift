import Darwin
import Foundation
import Metal

guard CommandLine.arguments.count == 2,
      let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue() else {
    fatalError("Need a Stefano folder and a Metal device")
}
let path = CommandLine.arguments[1] + "/readonly-metal-probe.f32"
let count = 65_536
let bytes = count * MemoryLayout<Float>.size
let writer = open(path, O_CREAT | O_EXCL | O_RDWR, 0o600)
guard writer >= 0, ftruncate(writer, off_t(bytes)) == 0 else {
    fatalError("Cannot create probe file")
}
let writeMap = mmap(nil, bytes, PROT_READ | PROT_WRITE,
                    MAP_SHARED, writer, 0)!
guard writeMap != MAP_FAILED else { fatalError("Cannot map writer") }
let values = writeMap.bindMemory(to: Float.self, capacity: count)
for i in 0..<count { values[i] = Float(i % 101) / 101 }
guard msync(writeMap, bytes, MS_SYNC) == 0 else {
    fatalError("Cannot flush test file")
}
munmap(writeMap, bytes)
close(writer)
let reader = open(path, O_RDONLY)
guard reader >= 0 else { fatalError("Cannot reopen read-only") }
let readMap = mmap(nil, bytes, PROT_READ, MAP_SHARED, reader, 0)!
guard readMap != MAP_FAILED else { fatalError("Cannot map read-only") }
defer {
    munmap(readMap, bytes)
    close(reader)
    unlink(path)
}
let input = device.makeBuffer(bytesNoCopy: readMap, length: bytes,
    options: .storageModeShared, deallocator: nil)
guard let input = input,
      let output = device.makeBuffer(length: bytes,
                                    options: .storageModeShared) else {
    fatalError("Metal rejected read-only mmap")
}
let shader = """
#include <metal_stdlib>
using namespace metal;
kernel void read_only(device const float* source [[buffer(0)]],
                      device float* target [[buffer(1)]],
                      uint id [[thread_position_in_grid]]) {
  if (id < 65536u) target[id] = source[id] * 2.0f;
}
"""
let library = try device.makeLibrary(source: shader, options: nil)
let pipeline = try device.makeComputePipelineState(
    function: library.makeFunction(name: "read_only")!)
let command = queue.makeCommandBuffer()!
let encoder = command.makeComputeCommandEncoder()!
encoder.setComputePipelineState(pipeline)
encoder.setBuffer(input, offset: 0, index: 0)
encoder.setBuffer(output, offset: 0, index: 1)
encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
    threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
encoder.endEncoding()
command.commit()
command.waitUntilCompleted()
guard command.status == .completed else {
    fatalError("Metal GPU read failed: \(String(describing: command.error))")
}
let result = output.contents().bindMemory(to: Float.self, capacity: count)
for i in 0..<count {
    let expected = Float(i % 101) / 101 * 2
    guard abs(result[i] - expected) < 1.0e-6 else {
        fatalError("Read-only GPU mismatch at \(i)")
    }
}
print("DEVICE \(device.name)")
print("READONLY_MAPPED_GPU_READ_PASS rows=\(count) bytes=\(bytes)")
