import Foundation
import Metal

guard CommandLine.arguments.count == 2,
      let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue() else {
    fatalError("Metal device or probe argument unavailable")
}
let source = try String(contentsOfFile: CommandLine.arguments[1],
                        encoding: .utf8)
let library = try device.makeLibrary(source: source, options: nil)
guard let function = library.makeFunction(name: "atomic64_probe") else {
    fatalError("Atomic64 function missing")
}
let pipeline = try device.makeComputePipelineState(function: function)
guard let buffer = device.makeBuffer(length: MemoryLayout<UInt64>.size,
                                     options: .storageModeShared),
      let command = queue.makeCommandBuffer(),
      let encoder = command.makeComputeCommandEncoder() else {
    fatalError("Metal probe buffer or command unavailable")
}
buffer.contents().storeBytes(of: UInt64(0), as: UInt64.self)
encoder.setComputePipelineState(pipeline)
encoder.setBuffer(buffer, offset: 0, index: 0)
encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                        threadsPerThreadgroup:
                            MTLSize(width: 1, height: 1, depth: 1))
encoder.endEncoding()
command.commit()
command.waitUntilCompleted()
let value = buffer.contents().load(as: UInt64.self)
guard command.status == .completed, value == 1 else {
    fatalError("Atomic64 dispatch did not produce 1")
}
print("ATOMIC64_RUNTIME_PASS", device.name, value)
