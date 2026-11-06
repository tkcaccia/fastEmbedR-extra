import Darwin
import Foundation
import Metal

guard CommandLine.arguments.count == 2,
      let device = MTLCreateSystemDefaultDevice() else {
    print("Missing output directory or Metal device")
    exit(1)
}
let directory = CommandLine.arguments[1]
let path = directory + "/mapped-buffer-probe.f32"
let count = 65_536
let bytes = count * MemoryLayout<Float>.size
let fd = open(path, O_CREAT | O_TRUNC | O_RDWR, 0o600)
guard fd >= 0, ftruncate(fd, off_t(bytes)) == 0 else {
    print("Cannot create mapped test file")
    exit(1)
}
let raw = mmap(nil, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
guard raw != MAP_FAILED, let mapped = raw else {
    print("Cannot map test file")
    close(fd)
    unlink(path)
    exit(1)
}
defer {
    munmap(mapped, bytes)
    close(fd)
    unlink(path)
}
let values = mapped.bindMemory(to: Float.self, capacity: count)
for i in 0..<count { values[i] = Float(i % 97) / 97 }
var input = device.makeBuffer(bytesNoCopy: mapped, length: bytes,
    options: .storageModeShared, deallocator: nil)
guard input != nil, let output = device.makeBuffer(length: bytes,
    options: .storageModeShared) else {
    print("Metal rejected memory-mapped buffer")
    exit(1)
}
let source = """
#include <metal_stdlib>
using namespace metal;
kernel void probe(device const float* source [[buffer(0)]],
                  device float* target [[buffer(1)]],
                  uint id [[thread_position_in_grid]]) {
    if (id < 65536u) target[id] = source[id] + 1.0f;
}
"""
let library = try device.makeLibrary(source: source, options: nil)
guard let function = library.makeFunction(name: "probe"),
      let queue = device.makeCommandQueue() else {
    print("Cannot create Metal probe pipeline")
    exit(1)
}
let pipeline = try device.makeComputePipelineState(function: function)
guard let command = queue.makeCommandBuffer(),
      let encoder = command.makeComputeCommandEncoder() else {
    print("Cannot create Metal command buffer")
    exit(1)
}
encoder.setComputePipelineState(pipeline)
encoder.setBuffer(input, offset: 0, index: 0)
encoder.setBuffer(output, offset: 0, index: 1)
encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
    threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
encoder.endEncoding()
command.commit()
command.waitUntilCompleted()
guard command.status == .completed else {
    print("Metal command failed: \(String(describing: command.error))")
    exit(1)
}
let result = output.contents().bindMemory(to: Float.self, capacity: count)
for i in 0..<count {
    if abs(result[i] - values[i] - 1) > 1.0e-6 {
        print("Mapped GPU read differed at row \(i)")
        exit(1)
    }
}
input = nil
print("DEVICE \(device.name)")
print("MAX_BUFFER_BYTES \(device.maxBufferLength)")
print("RECOMMENDED_WORKING_SET_BYTES \(device.recommendedMaxWorkingSetSize)")
print("MAPPED_GPU_READ_PASS rows=\(count) bytes=\(bytes)")
